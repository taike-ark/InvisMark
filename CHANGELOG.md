# 更新日志

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-11-15

首个可运行的开源参考实现（对应项目说明书的 M0/M1 之间）。

### 新增

- **算法内核** `invismark/core/`
  - 两级 Haar DWT + 4×4 分块 DCT + 归一化 AC 系数扩频调制（α 可调）
  - Reed–Solomon RS(64,24)：缩短自 RS(255,215)，Berlekamp–Massey + Chien + Forney，纯 Python
  - 24 字节追溯码（base36 资源码 + u16 用户索引 + u32 分钟时间 + 序号 + CRC32 + 保留位）
  - 纯 Python PNG 编解码（8/16 bit、灰度/RGB/调色板/RGBA、白底合成），PNG 零第三方依赖
  - 差异回注、YCbCr 色度保留、PSNR/SSIM 指标
- **业务层** `service.py`：嵌入 / 提取 / 追溯 / 证据包 / 离线号段 / 配额
- **存储层** `store.py`：SQLite（租户、用户索引映射、资产、追溯、提取日志、审计哈希链）
- **证据包** `evidence.py`：ZIP + manifest + 独立校验脚本 `verify.py`
- **CLI** `invismark`（`python -m invismark`）：demo / embed / extract / batch / trace / evidence / verify / serve / gui
- **HTTP API**（stdlib `http.server`）：`/v1/embed`、`/v1/extract`、`/v1/traces/{id}`、`/v1/reports`、`/v1/quota`、`/v1/traces/reserve`、`/v1/chain/verify`
- **桌面端**（Tkinter）：单图/批量/证据包/审计链，本地离线
- **移动端脚手架**（Flutter，液态玻璃三档降级）
- **工程化**：59 个 unittest、CI、Dockerfile / compose、鲁棒性矩阵跑批脚本、Apache-2.0 许可与社区文件

### 已知限制

- 中心裁剪后无法提取（块网格相位失配），路线图 v0.2 用同步头解决
- 长边小于 2400 px 的图会先放大到基准，SNR 有 3–6 dB 损失
- 大面积纯色 + 细线文字场景检出率低
- JPEG 攻击矩阵未实测（解码 JPEG 需 Pillow）
- 与 wmforge / blind-watermark 不保证位级兼容

- **桌面端界面重构（Fluent / WinUI）**：新增 `desktop-fluent/`（WPF + Fluent：左侧导航、卡片、
  圆角、深浅色跟随系统）与 `desktop-winui/`（WinUI 3 + Windows App SDK 1.7），后端统一调用
  `InvisMarkCLI.exe`，覆盖嵌入/检测/批量/证据包/审计链校验。WinUI 3 版本已在 Visual Studio 18
  环境下用 MSBuild 构建并运行验证。### 修复

- **手机端选图后加不上水印**：系统文件选择器在部分 ROM 上返回的 URI 读不出字节（表现为选完图没反应），
  改为**内置相册**（直接查 MediaStore 列表 + 缩略图 + 按需读原图），首页与检测页共用。
  同时把大图处理的内存压下来（Float32 缓冲、输入长边 1600 预降采样、PNG CRC 流式计算、largeHeap），
  并补了模态进度提示与「设置 → 本地引擎自检」。实机验证：自检通过、嵌入 PSNR 45.9 dB、
  保存到相册、检测命中 100%（截图见 `docs/apk-*-screenshot.png`）。
- **Android 启动崩溃**（`ClassNotFoundException: MainActivity`）：Flutter 3.50 模板的入口是 Kotlin 版
  `MainActivity.kt`，在当前工具链（AGP 9.3.1 + `android.builtInKotlin=false`）下 Kotlin 源未被编译，
  dex 缺少入口类。已改为 Java 版 `MainActivity.java`（javac 始终参与），并在 vivo V1921A / Android 10
  上实机验证启动与首页渲染正常。详见 `docs/PACKAGING.md` §2 第 5 条。
- **手机端改为独立离线运行**：水印引擎移植到 Dart（`apps/mobile/lib/core/`），嵌入/提取在本机完成，
  不再依赖服务端；设置页可切回服务端模式。
- **桌面端数据目录**：SQLite 默认落 `%APPDATA%\InvisMark\`，启动失败弹窗提示，不再因只读 cwd 闪退。

