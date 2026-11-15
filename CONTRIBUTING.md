# 贡献指南

感谢你愿意改进隐迹 InvisMark。这个项目刻意保持"零第三方依赖 + 纯 Python 可读"，所以
贡献时请优先考虑**小、可读、可验证**的实现，而不是引入大依赖。

## 开发环境

```bash
git clone https://github.com/invismark/invismark.git
cd invismark
python -m venv .venv && . .venv/Scripts/activate   # Windows: .venv\Scripts\activate
pip install numpy                # 唯一必需依赖
pip install pillow               # 可选：JPEG/WebP 读写
```

> 想用 `pip install -e .` 开发安装的话，需要 `setuptools>=61` 与 `wheel`（纯离线机器请先准备好这两个包）。
> 不安装也能直接用：在仓库根目录跑 `python -m invismark ...`，`PYTHONPATH` 指向仓库根即可。

## 必跑的检查

```bash
python -m unittest discover -s tests -t .        # 59 个测试，约 9 秒
python -m invismark demo --out demo              # 端到端闭环
python scripts/bench_matrix.py --width 800 --height 600   # 改算法时跑，别让矩阵退化
```

CI 会在 Python 3.10 / 3.11 / 3.12 上跑上面第 1、2 条。

## 提 PR 的约定

1. **一个 PR 一件事**：修 bug 不要顺手重构，新增攻击支持不要混格式化。
2. **算法改动必须附数据**：贴出 `bench_matrix.py` 改动前后的对比（检出/PSNR/耗时），
   并说明性质是"提升鲁棒性"还是"提升画质"——两者是互换关系。
3. **不要降低已知基线**：任何让 `test_pipeline` 中噪声/缩放/模糊用例变红的改动都会被要求修回。
4. **保持零依赖**：新增运行时依赖需要先在 issue 里达成共识；标准库能满足的一律用标准库。
5. **中文注释**：代码注释与提交信息可用中文；对外接口/文档术语与 README 保持一致。

## 提交信息

建议用便于生成 changelog 的前缀：

```
feat(core): 支持裁剪同步头（多相 tile）
fix(api): multipart 解析在无 filename 时崩溃
docs: 补充 JPEG 攻击矩阵实测
test: 增加调色板 PNG 解码用例
```

## 报告问题

- **普通 bug / 需求**：用 issue 模板，附最小复现（图片可脱敏）。
- **安全漏洞**：不要开公开 issue，按 [SECURITY.md](SECURITY.md) 私下联系。
- **检出率争议**：请附"原图 + 被怀疑图 + seed 版本 + 攻击步骤"，我们能据此复现。

## 行为准则

参与本项目即表示同意遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 许可

贡献的代码默认按 [Apache-2.0](LICENSE) 许可；提交 PR 即表示你有权以该许可提交。
