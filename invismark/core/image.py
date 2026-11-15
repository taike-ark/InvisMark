# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""图像读写、色彩空间、缩放与画质指标。

默认零依赖：PNG 走内置编解码器；JPEG / WebP / HEIC 等需要 Pillow（可选依赖
``pip install invismark[pillow]``），未安装时给出明确报错而不是静默失败。
"""

from __future__ import annotations

import os
from typing import Tuple

import numpy as np

from . import png

SUPPORTED_PNG = (".png",)
SUPPORTED_PILLOW = (".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff", ".heic", ".avif")


class ImageIOError(RuntimeError):
    """无法解码/编码该图片格式。"""


def _pillow():
    try:
        from PIL import Image  # type: ignore

        return Image
    except Exception:  # pragma: no cover - 取决于运行环境
        return None


def load_bytes(data: bytes) -> np.ndarray:
    """按魔数识别格式并解码为 (H, W, 3) uint8 RGB。"""
    if data.startswith(png.PNG_SIGNATURE):
        return png.decode(data)
    Image = _pillow()
    if Image is None:
        raise ImageIOError(
            "only PNG is supported without Pillow; install optional deps: pip install invismark[pillow]"
        )
    import io

    try:
        with Image.open(io.BytesIO(data)) as im:
            im = im.convert("RGB")
            return np.asarray(im, dtype=np.uint8).copy()
    except Exception as exc:  # pragma: no cover
        raise ImageIOError(f"cannot decode image: {exc}") from exc


def load(path: str | os.PathLike) -> np.ndarray:
    with open(path, "rb") as fh:
        return load_bytes(fh.read())


def save_bytes(rgb: np.ndarray, fmt: str = "png") -> bytes:
    fmt = fmt.lower().lstrip(".")
    if fmt == "png":
        return png.encode(rgb)
    Image = _pillow()
    if Image is None:
        raise ImageIOError("JPEG/WebP output requires Pillow: pip install invismark[pillow]")
    import io

    with io.BytesIO() as buf:
        Image.fromarray(np.ascontiguousarray(rgb)).save(buf, format=fmt.upper())
        return buf.getvalue()


def save(path: str | os.PathLike, rgb: np.ndarray) -> None:
    ext = os.path.splitext(str(path))[1].lower().lstrip(".")
    data = save_bytes(rgb, ext or "png")
    with open(path, "wb") as fh:
        fh.write(data)


# ---------------------------------------------------------------- 色彩


def to_ycbcr(rgb: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    r = rgb[..., 0].astype(np.float32)
    g = rgb[..., 1].astype(np.float32)
    b = rgb[..., 2].astype(np.float32)
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b
    return y, cb, cr


def from_ycbcr(y: np.ndarray, cb: np.ndarray, cr: np.ndarray) -> np.ndarray:
    y = y.astype(np.float32)
    cb = cb.astype(np.float32) - 128.0
    cr = cr.astype(np.float32) - 128.0
    r = y + 1.402 * cr
    g = y - 0.344136 * cb - 0.714136 * cr
    b = y + 1.772 * cb
    out = np.stack([r, g, b], axis=-1)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def to_gray(rgb: np.ndarray) -> np.ndarray:
    return (
        0.299 * rgb[..., 0].astype(np.float32)
        + 0.587 * rgb[..., 1].astype(np.float32)
        + 0.114 * rgb[..., 2].astype(np.float32)
    )


# ---------------------------------------------------------------- 缩放


def resize(arr: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    """双线性缩放；整数输入返回整数（四舍五入并裁剪），浮点输入返回 float32。"""
    out_h = int(out_h)
    out_w = int(out_w)
    src = np.asarray(arr)
    is_int = np.issubdtype(src.dtype, np.integer)
    h, w = src.shape[:2]
    if (h, w) == (out_h, out_w):
        return src.astype(np.float32) if is_int else src.astype(np.float32)
    if out_h <= 0 or out_w <= 0:
        raise ValueError("resize target must be positive")
    arrf = src.astype(np.float32)
    ys = (np.arange(out_h, dtype=np.float32) + 0.5) * (h / out_h) - 0.5
    xs = (np.arange(out_w, dtype=np.float32) + 0.5) * (w / out_w) - 0.5
    y0 = np.floor(ys).astype(np.int64)
    x0 = np.floor(xs).astype(np.int64)
    wy = (ys - y0).astype(np.float32)
    wx = (xs - x0).astype(np.float32)
    y0 = np.clip(y0, 0, h - 1)
    x0 = np.clip(x0, 0, w - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    if arrf.ndim == 2:
        wx_h, wy_v = wx[None, :], wy[:, None]
        top_rows = arrf[y0]
        bottom_rows = arrf[y1]
        top = top_rows[:, x0] * (1 - wx_h) + top_rows[:, x1] * wx_h
        bottom = bottom_rows[:, x0] * (1 - wx_h) + bottom_rows[:, x1] * wx_h
        out = top * (1 - wy_v) + bottom * wy_v
    else:
        wx_h, wy_v = wx[None, :, None], wy[:, None, None]
        top_rows = arrf[y0]
        bottom_rows = arrf[y1]
        top = top_rows[:, x0] * (1 - wx_h) + top_rows[:, x1] * wx_h
        bottom = bottom_rows[:, x0] * (1 - wx_h) + bottom_rows[:, x1] * wx_h
        out = top * (1 - wy_v) + bottom * wy_v
    if is_int:
        return np.clip(np.rint(out), 0, 255).astype(src.dtype)
    return out.astype(np.float32)


def fit_long_edge(h: int, w: int, long_edge: int, multiple: int = 8) -> Tuple[int, int]:
    """按长边等比缩放到 long_edge，并把两边就近对齐到 multiple 的整数倍。"""
    scale = float(long_edge) / float(max(h, w))
    nh = max(multiple, int(round(h * scale)))
    nw = max(multiple, int(round(w * scale)))
    nh = max(multiple, int(round(nh / multiple)) * multiple)
    nw = max(multiple, int(round(nw / multiple)) * multiple)
    return nh, nw


# ---------------------------------------------------------------- 指标


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    """PSNR（dB）；完全相同时返回 inf。"""
    d = a.astype(np.float64) - b.astype(np.float64)
    mse = float(np.mean(d * d))
    if mse == 0.0:
        return float("inf")
    return float(10.0 * np.log10(255.0 * 255.0 / mse))


def _box_mean(img: np.ndarray, win: int) -> np.ndarray:
    """可分离滑动窗口均值（cumsum 实现，边缘按有效像素数归一）。"""
    pad = win // 2
    h, w = img.shape
    p = np.pad(img, ((pad, pad), (pad, pad)), mode="reflect")
    c = np.cumsum(np.cumsum(p, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)), mode="constant")
    s = (
        c[win:, win:]
        - c[:-win, win:]
        - c[win:, :-win]
        + c[:-win, :-win]
    )
    return s / float(win * win)


def ssim(a: np.ndarray, b: np.ndarray, win: int = 8) -> float:
    """全局 SSIM（灰度、均匀窗口，工程用近似值）。"""
    x = to_gray(a) if a.ndim == 3 else a.astype(np.float32)
    y = to_gray(b) if b.ndim == 3 else b.astype(np.float32)
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    mu_x = _box_mean(x, win)
    mu_y = _box_mean(y, win)
    sigma_x = _box_mean(x * x, win) - mu_x * mu_x
    sigma_y = _box_mean(y * y, win) - mu_y * mu_y
    sigma_xy = _box_mean(x * y, win) - mu_x * mu_y
    num = (2 * mu_x * mu_y + c1) * (2 * sigma_xy + c2)
    den = (mu_x * mu_x + mu_y * mu_y + c1) * (sigma_x + sigma_y + c2)
    return float(min(1.0, np.mean(num / den)))
