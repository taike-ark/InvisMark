# 路线图

> 把[项目说明书](wmforge-隐形水印项目说明书.md)的 M0–M5 映射到本仓库的实际进度。
> 说明书是"产品要什么"，本文是"这个开源实现现在有什么、下一步做什么"。

## 已完成（v0.1 参考实现）

- [x] 算法内核：两级 DWT + 分块 DCT + 归一化 AC 扩频 + RS(64,24)
- [x] 24 字节追溯码（CRC32 + 保留位双门限）
- [x] 纯 Python PNG 编解码（PNG 零第三方依赖）
- [x] 差异回注、YCbCr 色度保留、PSNR/SSIM
- [x] SQLite 存储：租户 / 用户索引映射 / 资产 / 追溯 / 提取日志 / 审计哈希链
- [x] 证据包 + 独立 `verify.py`（离开系统也能验）
- [x] CLI（demo/embed/extract/batch/trace/evidence/verify/serve/gui）
- [x] 零依赖 HTTP API（stdlib）
- [x] Tkinter 桌面端（本地离线）
- [x] Flutter 移动端脚手架（液态玻璃三档降级）
- [x] 59 个 unittest + 鲁棒性矩阵跑批 + CI + Docker
- [x] Apache-2.0 许可与社区文件

## v0.2 · 鲁棒性（对齐说明书 M0）

- [ ] **裁剪同步头**：4 相位 tile + 已知前缀，提取端估计尺度/相位（解决 A4 裁剪）
- [ ] **JPEG 攻击矩阵**：`pip install pillow` 后补 A1（q95/q75/q60/q30）与 A2（长边 1280 q60）
- [ ] **正/负样本库**：1000 正 + 10000 负，按题材/尺寸/亮度分桶（说明书 §12.2）
- [ ] **小图策略**：长边 < 2400 时不放大，改用与尺寸匹配的级数（提取端按 EXIF/尺寸推断）
- [ ] 误报率实测：10 000 张负样本，目标 ≤1e-4

## v0.3 · 多租户与服务化（对齐 M1/M4）

- [ ] 提取端按租户自动试 seed（`seed_for(tenant)` × `seed_version`）
- [ ] 租户鉴权：JWT + 设备码 + 限流 + 计量
- [ ] 对象存储：MinIO/S3（大图、成图、证据包），生命周期策略
- [ ] 任务队列：批量嵌入异步化 + 断点续传
- [ ] Web 后台：租户/用户/配额/审计/证据管理

## v1.0 · 产品化

- [ ] FastAPI 适配层（业务层已解耦，替换 HTTP 层即可）
- [ ] KMS 托管根 seed + 双人审批导出 + 轮换
- [ ] RFC 3161 第三方时间戳（证据包时间可信度）
- [ ] PySide6 桌面端（批量队列、进度、失败重试）替代 Tkinter MVP
- [ ] Flutter 双端接入真实相册/相机/分享
- [ ] Docker Compose / Helm / Grafana 面板
- [ ] 与 wmforge 的兼容层（需要交叉提取时）

## 不打算做

- 视频/音频水印（超出范围）
- 可证明对抗去水印的工具（研究问题，且与产品承诺矛盾）
- "任意长文本水印"（载荷 24 B 是硬约束，长文本走元数据）

## 参与

想认领某一项，请在 issue 里说明，或直接按 [CONTRIBUTING.md](../CONTRIBUTING.md) 提 PR。
改算法的 PR 必须附 `scripts/bench_matrix.py` 的前后对比数据。
