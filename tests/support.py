# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""测试辅助：合成图像与常见攻击（只依赖 numpy）。"""

from __future__ import annotations

import numpy as np

from invismark.core import image as imio


def synth(width: int = 800, height: int = 600, seed: int = 0, noise: float = 12.0) -> np.ndarray:
    """带纹理的合成图：渐变底色 + 圆斑 + 噪声，足以触发中频能量。"""
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
    img += rng.normal(0, noise, img.shape)
    return np.clip(img, 0, 255).astype(np.uint8)


def add_noise(img: np.ndarray, sigma: float, seed: int = 1) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return np.clip(img.astype(np.float32) + rng.normal(0, sigma, img.shape), 0, 255).astype(np.uint8)


def scale(img: np.ndarray, factor: float) -> np.ndarray:
    h, w = img.shape[:2]
    return imio.resize(img, max(8, int(h * factor)), max(8, int(w * factor)))


def jitter_brightness(img: np.ndarray, gain: float = 1.06, bias: float = 4.0) -> np.ndarray:
    return np.clip(img.astype(np.float32) * gain + bias, 0, 255).astype(np.uint8)


def blur3(img: np.ndarray) -> np.ndarray:
    k = np.array([1.0, 2.0, 1.0]) / 4.0
    y = img.astype(np.float32)
    pad = np.pad(y, ((1, 1), (0, 0), (0, 0)), mode="edge")
    y = k[0] * pad[:-2] + k[1] * pad[1:-1] + k[2] * pad[2:]
    pad = np.pad(y, ((0, 0), (1, 1), (0, 0)), mode="edge")
    y = k[0] * pad[:, :-2] + k[1] * pad[:, 1:-1] + k[2] * pad[:, 2:]
    return np.clip(y, 0, 255).astype(np.uint8)
