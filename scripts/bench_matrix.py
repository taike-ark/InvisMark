# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""鲁棒性矩阵跑批：对同一张图做多种二次处理，输出检出率表（Markdown / CSV）。

用法::

    python scripts/bench_matrix.py --width 1600 --height 1200 --out bench.md

说明：这里是**参考实现的实测基线**，不是产品承诺。产品交付前应按
docs/wmforge-隐形水印项目说明书.md §12.1 扩充到正/负样本库并逐题材分桶。
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import time
from pathlib import Path

import numpy as np

from invismark.core import image as imio
from invismark.core import pipeline, trace


def synth(width: int, height: int, seed: int = 0, texture: float = 14.0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    x = np.linspace(0, 255, width, dtype=np.float32)[None, :]
    y = np.linspace(0, 255, height, dtype=np.float32)[:, None]
    base = 0.6 * x + 0.4 * y
    img = np.stack([base, base * 0.85 + 30.0, base * 0.7 + 55.0], axis=-1)
    yy, xx = np.mgrid[0:height, 0:width]
    for cx, cy, r, amp in [
        (width * 0.3, height * 0.4, min(width, height) * 0.25, 60),
        (width * 0.7, height * 0.6, min(width, height) * 0.18, -50),
    ]:
        mask = ((xx - cx) ** 2 + (yy - cy) ** 2) < r * r
        img[mask] += amp
    img += rng.normal(0, texture, img.shape)
    return np.clip(img, 0, 255).astype(np.uint8)


def photo_like(width: int, height: int, seed: int = 3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    acc = np.zeros((height, width), np.float32)
    for octave, amp in ((1, 60), (2, 30), (4, 16), (8, 8), (16, 4)):
        small = rng.normal(0, amp, (max(2, height // (16 * octave)), max(2, width // (16 * octave))))
        acc += np.asarray(imio.resize(small, height, width), np.float32)
    acc = (acc - acc.min()) / max(acc.max(), 1e-6) * 220 + 20
    img = np.stack([acc, acc * 0.85 + 20, acc * 0.7 + 35], -1)
    return np.clip(img, 0, 255).astype(np.uint8)


def attacks(img: np.ndarray) -> dict[str, np.ndarray]:
    def noise(sigma: float, seed: int = 1) -> np.ndarray:
        rng = np.random.default_rng(seed)
        return np.clip(img.astype(np.float32) + rng.normal(0, sigma, img.shape), 0, 255).astype(np.uint8)

    def resize(f: float) -> np.ndarray:
        h, w = img.shape[:2]
        return imio.resize(img, max(8, int(h * f)), max(8, int(w * f)))

    def bright(gain: float = 1.06, bias: float = 4.0) -> np.ndarray:
        return np.clip(img.astype(np.float32) * gain + bias, 0, 255).astype(np.uint8)

    def blur() -> np.ndarray:
        k = np.array([1.0, 2.0, 1.0]) / 4.0
        y = img.astype(np.float32)
        pad = np.pad(y, ((1, 1), (0, 0), (0, 0)), mode="edge")
        y = k[0] * pad[:-2] + k[1] * pad[1:-1] + k[2] * pad[2:]
        pad = np.pad(y, ((0, 0), (1, 1), (0, 0)), mode="edge")
        y = k[0] * pad[:, :-2] + k[1] * pad[:, 1:-1] + k[2] * pad[:, 2:]
        return np.clip(y, 0, 255).astype(np.uint8)

    def crop(f: float) -> np.ndarray:
        h, w = img.shape[:2]
        nh, nw = int(h * f), int(w * f)
        y0, x0 = (h - nh) // 2, (w - nw) // 2
        return img[y0:y0 + nh, x0:x0 + nw]

    return {
        "A0 原始成图": img,
        "A1 PNG 重存": imio.load_bytes(imio.save_bytes(img)),
        "A2 高斯噪声 σ=3": noise(3.0),
        "A3 亮度对比度 +6%": bright(),
        "A4 3×3 模糊": blur(),
        "A5 缩放 0.75×": resize(0.75),
        "A6 缩放 0.5×": resize(0.5),
        "A7 放大 2×": resize(2.0),
        "A8 中心裁剪 80%": crop(0.8),
    }


def run_case(name: str, img: np.ndarray, seed: int, base: int, rows: list[dict], alpha: float) -> None:
    code = trace.TraceCode.new("F13241", 7)
    t0 = time.perf_counter()
    res = pipeline.embed(img, code, seed, alpha=alpha, base_long_edge=base)
    embed_ms = (time.perf_counter() - t0) * 1000
    for label, attacked in attacks(res.image).items():
        got = pipeline.extract(attacked, seed, base_long_edge=base)
        rows.append({
            "image": name,
            "attack": label,
            "found": got.found,
            "confidence": round(got.confidence, 3),
            "corrected_bytes": got.corrected_bytes,
            "psnr_db": round(res.psnr, 2) if res.psnr != float("inf") else "inf",
            "embed_ms": round(embed_ms),
            "extract_ms": round(got.elapsed_ms),
        })
    # 负样本（无水印图）与错误 seed 各跑一次
    neg = pipeline.extract(photo_like(img.shape[1], img.shape[0], seed=99), seed, base_long_edge=base)
    rows.append({"image": name, "attack": "A9 无水印负样本", "found": neg.found,
                 "confidence": round(neg.confidence, 3), "corrected_bytes": 0,
                 "psnr_db": "-", "embed_ms": "-", "extract_ms": round(neg.elapsed_ms)})
    wrong = pipeline.extract(res.image, seed + 1, base_long_edge=base)
    rows.append({"image": name, "attack": "A10 错误 seed", "found": wrong.found,
                 "confidence": round(wrong.confidence, 3), "corrected_bytes": 0,
                 "psnr_db": "-", "embed_ms": "-", "extract_ms": round(wrong.elapsed_ms)})


def main() -> int:
    ap = argparse.ArgumentParser(description="invisMark 鲁棒性矩阵跑批")
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--height", type=int, default=1200)
    ap.add_argument("--base", type=int, default=pipeline.BASE_LONG_EDGE)
    ap.add_argument("--seed", type=int, default=20260115)
    ap.add_argument("--alpha", type=float, default=pipeline.DEFAULT_ALPHA)
    ap.add_argument("--out", default="")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    rows: list[dict] = []
    for name, maker in (("合成纹理图", synth), ("类自然照片", photo_like)):
        run_case(name, maker(args.width, args.height, seed=0), args.seed, args.base, rows, args.alpha)

    header = ["image", "attack", "found", "confidence", "corrected_bytes", "psnr_db", "embed_ms", "extract_ms"]
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=header)
    writer.writeheader()
    writer.writerows(rows)
    text = buf.getvalue()

    md = ["| 图像 | 攻击 | 检出 | 置信度 | 纠错字节 | PSNR(dB) | 嵌入ms | 提取ms |",
          "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append(
            f"| {r['image']} | {r['attack']} | {'OK' if r['found'] else 'NG'} | {r['confidence']} | "
            f"{r['corrected_bytes']} | {r['psnr_db']} | {r['embed_ms']} | {r['extract_ms']} |"
        )
    md_text = "\n".join(md) + "\n"
    Path(args.out).write_text(md_text, encoding="utf-8") if args.out else None
    try:
        print(md_text)
    except UnicodeEncodeError:  # Windows GBK 控制台
        print(md_text.encode("utf-8", "replace").decode("utf-8", "replace"))
    if args.json:
        Path(args.json).write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if all(r["found"] or r["attack"].startswith(("A9", "A10", "A8")) for r in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
