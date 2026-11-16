<div align="center">

# 隐迹 InvisMark

**图片盲水印 · 盗图溯源 · 版权取证**

DWT + 分块 DCT + 归一化 AC 扩频 + RS(64,24) 纠错 —— 24 字节追溯码，二次压缩后仍能恢复

[![License](https://img.shields.io/badge/license-Apache--2.0-22d3ee.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue.svg)](https://www.python.org)
[![Dependencies](https://img.shields.io/badge/runtime%20deps-numpy%20only-success.svg)](#零第三方依赖)
[![Tests](https://img.shields.io/badge/tests-59%20passing-brightgreen.svg)](tests/)

</div>

---

## 它是什么

给一张图嵌入 24 字节的**追溯码**（`trace_id`），肉眼不可见；从"一张被压缩、缩放、截图、转发过的图"里把它读回来，反查到 **租户 / 用户 / 资源 / 分钟级嵌入时间**。

它解决的是**事后举证**问题：原图被转存两次后 EXIF 和文件哈希全部失效，可见水印又被裁掉或抹掉，此时你还需要证明"这张图原本是我的/是哪个账号泄露的"。

```bash
# 跑通闭环只需三步，唯一依赖是 numpy
python -m invismark demo --out demo
```

```
{
  "psnr": 47.4, "ssim": 0.998,
  "trace_id": "01362B6A7100070037279600000000D9083B2A0000000000",
  "found": true, "corrected_bytes": 0
}
```

## 它不是什么（先读这段，避免错误承诺）

| 能力 | 状态 | 说明 |
|---|---|---|
| 盲提取（不需要原图） | ✅ | 只用 seed 即可提取 |
| 抗 PNG 重存 / 亮度对比度 / 加噪 / 缩放 / 放大 | ✅ 实测通过 | 见下方[能力矩阵](#实测能力基线) |
| 抗中心裁剪 | ❌ 参考实现不支持 | 裁剪会同时改变尺度与块网格相位；路线图（多相 tile + 同步头） |
| 任意长文本水印 | ❌ | 载荷固定 24 B，只放追溯码；长文本走 XMP/IPTC |
| 抗蓄意去水印（如 WmForger 类黑盒攻击） | ❌ | 商用承诺应限定为"非针对性攻击"，见说明书 §12.4 |
| 阻断复制（DRM） | ❌ | 只做事后追溯，不防拷贝 |
| JPEG 压缩实测 | ⚠️ 待补 | 解码 JPEG 需 `pip install pillow`；参考实现只对 PNG 做了全链路实测，JPEG 攻击矩阵属 M0 任务 |

## 为什么能扛二次压缩

三个正交的设计取向，各自解决一类失真：

| 设计 | 作用 | 对应攻击 |
|---|---|---|
| **两级 DWT + 16 像素块** | 把比特放在"内容尺度"而不是像素尺度 | 缩放、平台二次压缩、模糊 |
| **归一化 AC 系数**（`C(1,1)/‖AC‖`，注入 `±α·‖AC‖`） | 整体增益被分子分母约掉 | 亮度/对比度/色彩调整、等比缩放 |
| **每比特 K 块扩频 + 去偏置 + RS(64,24)** | 单块干扰被平均，最多纠 20 字节错误 | 噪声、局部纹理干扰、重编码误码 |

追溯码本身再叠两道校验：**CRC32 + 保留位**，只有 RS 解码成功且 CRC 通过才算命中——这是压低误报（目标 ≤ 1e-4）的第二道门限。

## 实测能力基线

`python scripts/bench_matrix.py --width 2400 --height 1800` 的真实输出（Windows / Python 3.11 / numpy 2.4，单核）：

| 图像 | 攻击 | 检出 | 纠错字节 | 嵌入耗时 |
|---|---|---|---|---|
| 合成纹理图 | 原始 / PNG 重存 / 噪声 σ=3 / 亮度+6% / 3×3 模糊 / 缩放 0.5×·0.75×·2× | ✅ 全部 | 0 | 1.9 s |
| 合成纹理图 | 中心裁剪 80% | ❌ | — | — |
| 类自然照片 | 原始 / PNG 重存 / 噪声 σ=3 / 亮度+6% / 3×3 模糊 / 缩放 0.5×·0.75×·2× | ✅ 全部 | 0 | 1.8 s |
| 类自然照片 | 中心裁剪 80% | ❌ | — | — |
| 两者 | 无水印负样本 / 错误 seed | ❌（正确拒绝） | — | — |

嵌入后画质：**PSNR 45–47 dB、SSIM ≥ 0.99**（2400 px 基准，`alpha=0.6`）。`alpha` 可在 `0.3–0.8` 调节，画质与鲁棒性单调互换。

**已知会掉点的场景**（诚实列出）：

1. **长边 < 2400 px 的小图**：会先放大到基准再嵌入，回注/再放大带来约 3–6 dB 的等效 SNR 损失；建议直接用原图（≥ 2400 px）处理。
2. **大面积纯色 + 细线文字截图**：中频能量太集中，部分比特拿不到票；提高 `alpha` 或先补齐纹理。
3. **低纹理的平滑图 + 小尺寸**：鲁棒性取决于「每比特块数 k」（`k ≈ 基准像素数 / 4096`）。2400 px 时 k≈29–32 很稳；800 px 时 k 只有 14，平滑图会显著掉点——这也是 CI 快速基线只跑合成纹理图的原因。
4. **裁切**：见上表。

## 架构

```
            ┌────────────────────────── 客户端三形态 ──────────────────────────┐
            │  CLI (argparse)   桌面端 (Tkinter)   移动端 Flutter 脚手架        │
            └───────────────┬─────────────────────────────┬───────────────────┘
                            │ 进程内                           │ HTTPS / REST
                            ▼                                 ▼
            ┌───────────────────────────────────────────────────────────────┐
            │  service.py  业务层：配额 → 追溯码 → 嵌入/提取 → 落库 → 证据包   │
            └───────┬───────────────────────┬───────────────────────┬───────┘
                    ▼                       ▼                       ▼
        ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
        │ core/pipeline.py   │   │ store.py (SQLite)  │   │ evidence.py        │
        │ DWT→DCT→扩频→RS    │   │ 租户/映射/审计链    │   │ 哈希清单+链+verify │
        └────────────────────┘   └────────────────────┘   └────────────────────┘
                    ▲
        ┌───────────┴────────────────────────────────────────────────────────┐
        │ core/trace.py  24B 追溯码（base36 资源码 + u16 用户索引 + u32 分钟）│
        │ core/rs.py     RS(64,24)（BM + Chien + Forney，纯 Python）          │
        │ core/png.py    纯 Python PNG 编解码（唯一需要的 C 库是 numpy）      │
        └────────────────────────────────────────────────────────────────────┘
```

嵌入链路与提取链路、字节布局、参数含义见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 目录结构

```
InvisMark/
├─ invismark/            ← 零第三方依赖的 Python 包（算法 + 服务 + CLI + API + 桌面端）
│  ├─ core/              ← pipeline / rs / trace / png / image / gf256
│  ├─ api/               ← stdlib http.server 的 REST 服务
│  ├─ desktop/           ← Tkinter 桌面端（本地离线）
│  ├─ service.py store.py evidence.py config.py cli.py
├─ apps/mobile/          ← Flutter 双端脚手架（液态玻璃，见 design/ 概念稿）
├─ docs/                 ← 项目说明书、UI 规范、架构、API、路线图
├─ design/               ← 液态玻璃视觉概念稿（浏览器直接打开）
├─ tests/                ← 59 个 unittest（零 pytest 依赖）
├─ scripts/              ← 鲁棒性矩阵跑批
├─ deploy/               ← Dockerfile / docker-compose
└─ .github/workflows/    ← CI
```

## 零第三方依赖

运行时只需要 **numpy**。PNG 编解码、Reed–Solomon、HTTP 服务、SQLite、桌面 GUI 全部走 Python 标准库——
私有化/内网/断网机器 `pip install` 装不上别的包也能跑。JPEG/WebP 的读写才需要可选的 Pillow。

## 三种用法

### 1) 命令行

```bash
python -m invismark embed   --in photo.jpg --out photo.wm.png --user alice --resource F13241
python -m invismark extract --in photo.wm.png
python -m invismark batch   --in ./shots --out ./out --pattern "*.png"
python -m invismark evidence <trace_id> --out case-001.zip
python -m invismark verify            # 校验审计哈希链
python -m invismark gui               # 打开桌面端
```

### 2) HTTP API（零依赖）

```bash
python -m invismark serve --host 127.0.0.1 --port 8000
curl -X POST "http://127.0.0.1:8000/v1/embed?user=alice&resource_code=F13241" \
     -H "content-type: image/png" --data-binary @photo.png
```

端点、请求/响应示例、错误码见 [docs/API.md](docs/API.md)。

### 3) 桌面端

```bash
python -m invismark gui     # Windows/macOS 官方 Python 自带 tkinter
```

单图嵌入 / 单图检测 / 目录批量 / 导出证据包 / 校验审计链，全部本地完成，图片不出机器。
数据库默认落在 `%APPDATA%\InvisMark\invismark.db`（macOS/Linux 在 `~/.local/share/invismark/`），
可用环境变量 `INVISMARK_DB` 覆盖——避免从只读目录启动时无法写库。

#### 现代界面（Fluent 桌面版）

`desktop-fluent/` 是重写后的桌面端（WPF + Fluent 设计语言：左侧导航栏、卡片、圆角、
跟随系统深浅色），后端仍调用同一个 `InvisMarkCLI.exe`，算法与命令行/Python 完全一致。

```powershell
# 需要 .NET 8 SDK
dotnet publish desktop-fluent -c Release -r win-x64 --self-contained true -o dist\desktop
# 把 InvisMarkCLI.exe 放到 dist\desktop\backend\ 下再运行 InvisMarkDesktop.exe
```

Release 里也提供打包好的 `InvisMark-0.1.0-win64-desktop.zip`（自包含，不需要装 .NET）。

`desktop-winui/` 是同一套界面的 **WinUI 3** 版本（C#/XAML，Windows App SDK 1.7），
在装了 Visual Studio（含 .NET 桌面开发 + Windows App SDK 组件）的机器上用 MSBuild 构建：

```powershell
msbuild desktop-winui\InvisMarkDesktop.csproj /restore /t:Publish `
  /p:Configuration=Release /p:Platform=x64 /p:SelfContained=true /p:PublishDir=dist\winui\
```

### 4) 移动端（独立离线运行）

`apps/mobile/` 是 Flutter 双端 App，**默认本地离线模式**：水印嵌入/提取全部在手机上完成，
不联网、不上传图片，也不需要服务端。算法是 Python 参考实现的 Dart 移植
（两级 DWT + 4×4 DCT + 归一化 AC 扩频 + RS(64,24) + PNG 编解码），在手机端用独立 isolate 跑。

- 首次启动会在本机生成一个随机 seed（存本地），之后固定；换机/清数据后旧图无法用本机提取。
- 设置页可切换「服务端模式」，改用远端 `/v1/embed`、`/v1/extract`（需要自己部署服务端）。
- `apps/mobile/android/` 是完整 Android 平台工程（Java 版 `MainActivity`，零第三方插件提供
  选图/拍照/保存/分享），`flutter build apk --release` 即可出包。

详见 [apps/mobile/README.md](apps/mobile/README.md) 与 [移动端 UI 规范](docs/wmforge-移动端UI规范-液态玻璃.md)。

## 证据包：离开本系统也能验

`evidence <trace_id>` 生成的 ZIP 里除原图/成图哈希外，还带一个 **只用标准库的 `verify.py`**：

```bash
unzip case-001.zip -d case-001 && cd case-001 && python verify.py
# [ OK ] original.png
# [ OK ] watermarked.png
# [ OK ] chain.jsonl
# RESULT: PASS
```

任何人拿到这个包都能独立核对哈希与审计链，不需要信任我们的服务端——避免"自家系统证明自家结论"。

## 与 wmforge 的关系

本项目是[项目说明书](docs/wmforge-隐形水印项目说明书.md)配套的**独立开源参考实现**：

- 说明书里的产品形态、双端矩阵、证据链、合规设计**直接沿用**；
- 算法侧我方独立实现（DWT/DCT 扩频 + RS(64,24)），**不保证与 wmforge / blind-watermark 数值位级兼容**；
- 若要交付"与存量图交叉提取"的产品形态，需按说明书的 wmforge 路线替换 `core/pipeline.py`（接口保持不变）。

## 文档索引

| 文档 | 内容 | 什么时候看 |
|---|---|---|
| [项目说明书](docs/wmforge-隐形水印项目说明书.md) | 背景/目标/成功判据、双端形态、技术栈、19 条功能需求、API、数据模型、部署、里程碑、风险 | 立项评审、报价 |
| [架构与算法](docs/ARCHITECTURE.md) | 字节布局、变换链、扩频/去偏置、参数与取舍、实测方法与已知边界 | 改算法、做 M0 验证 |
| [API 参考](docs/API.md) | REST 端点、请求/响应、错误码、curl 示例 | 接客户端 |
| [移动端 UI 规范](docs/wmforge-移动端UI规范-液态玻璃.md) | 液态玻璃五层材质、Token、组件、三档降级、验收清单 | UI / Flutter |
| [视觉概念稿](design/mobile-glass-mockup.html) | 3 屏高保真，可调模糊半径/亮暗/降低透明度 | 确认视觉方向 |
| [路线图](docs/ROADMAP.md) | 参考实现 → 产品化差距、里程碑拆解 | 规划 |
| [打包说明](docs/PACKAGING.md) | 如何构建 Windows EXE（PyInstaller）与 Android APK（Flutter），含踩坑记录 | 发版 |
| [贡献指南](CONTRIBUTING.md) / [安全策略](SECURITY.md) | 提 PR、报漏洞 | 参与 |

## 安全与合规

- **隐私最小化**：水印里只有 `user_index`（整数），映射表在服务端；泄露的图不会直接暴露手机号/姓名。
- **seed 即权限**：同图必须同 seed 才能提取；租户级派生 seed（`settings.seed_for(tenant)`），轮换走 `seed_version`。
- **审计哈希链**：`this_hash = sha256(prev_hash + 规范化记录)`，任意一条被改都会在 `verify` 里暴露。
- **法规对齐**（说明书 §13）：PIPL 最小必要与可删除、数据安全法分级、AIGC 场景可承担《标识办法》的"隐式标识"角色。

## 路线图（摘要）

| 阶段 | 内容 | 状态 |
|---|---|---|
| **v0.1 参考实现**（当前） | 算法内核 + CLI + API + 桌面端 + 证据包 + 59 测试 | ✅ |
| v0.2 鲁棒性 | 裁剪同步头（多相 tile）、JPEG 攻击矩阵、正/负样本库 | ⏳ |
| v0.3 多租户 | 提取端按租户自动试 seed、配额与用量看板 | ⏳ |
| v1.0 产品化 | FastAPI 适配层、MinIO 存证、KMS、PySide6 客户端、Docker/Helm | ⏳ |

详见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 贡献

欢迎 issue / PR。提交前请先跑：

```bash
python -m unittest discover -s tests -t .   # 59 个测试，约 9 秒
python -m invismark demo --out demo          # 闭环自检
```

细则见 [CONTRIBUTING.md](CONTRIBUTING.md)；安全问题请走 [SECURITY.md](SECURITY.md) 的私下渠道，不要开公开 issue。

## 许可

[Apache-2.0](LICENSE)。商用、私有化、二次分发均可，保留版权与 NOTICE 即可；专利授权与商标条款见协议原文。
