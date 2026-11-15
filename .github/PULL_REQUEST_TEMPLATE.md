## 这个 PR 做了什么

<!-- 一句话说明 -->

## 类型

- [ ] bug 修复
- [ ] 新功能
- [ ] 算法/参数改进（必须附矩阵对比）
- [ ] 文档
- [ ] 工程化（CI/打包/部署）

## 自检

- [ ] `python -m unittest discover -s tests -t .` 全绿
- [ ] `python -m invismark demo --out demo` 通过
- [ ] 改了算法/参数：附 `scripts/bench_matrix.py` 改动前后对比（检出/PSNR/耗时）
- [ ] 新增运行时依赖？如是，已在 issue 达成共识并更新 `pyproject.toml` / README
- [ ] 文档已同步（README / docs/）
- [ ] 提交信息符合 `feat/fix/docs/test` 前缀

## 对比数据（算法类 PR 必填）

| 场景 | 改动前 | 改动后 |
|---|---|---|
| PSNR / SSIM | | |
| 缩放 0.5× 检出 | | |
| 噪声 σ=3 检出 | | |
| 嵌入耗时 | | |
