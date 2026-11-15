# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""纯 Python PNG 编解码（零第三方依赖）。

支持：8/16 bit、灰度/RGB/调色板/灰度+Alpha/RGBA、非隔行；解码统一输出
``uint8 RGB``（Alpha 按白底合成，与算法侧「白底压暗」一致）。

编码固定输出 8 bit RGB、非隔行、filter=None，保证跨平台可读；
文件大小略大，但对水印管线无影响（存证用的原图可另存高压缩副本）。
"""

from __future__ import annotations

import struct
import zlib
from typing import Tuple

import numpy as np

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PNGError(ValueError):
    """PNG 结构损坏或不受支持（隔行/位深等）。"""


def _chunks(data: bytes):
    pos = len(PNG_SIGNATURE)  # 跳过 8 字节签名
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        crc = data[pos + 8 + length : pos + 12 + length]
        if len(body) != length or len(crc) != 4:
            raise PNGError("truncated PNG chunk")
        yield ctype, body
        pos += 12 + length


def _unfilter(raw: bytes, width: int, height: int, bpp: int, stride: int) -> np.ndarray:
    """逐行反滤波，返回 (height, stride) uint8。"""
    out = np.empty((height, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.uint8)
    pos = 0
    for y in range(height):
        if pos >= len(raw):
            raise PNGError("PNG data shorter than expected")
        ftype = raw[pos]
        line = raw[pos + 1 : pos + 1 + stride]
        if len(line) != stride:
            raise PNGError("truncated PNG scanline")
        pos += 1 + stride
        if ftype == 0:  # None
            row = np.frombuffer(line, dtype=np.uint8).copy()
        elif ftype == 2:  # Up
            row = (np.frombuffer(line, dtype=np.uint8) + prev) & 0xFF
            row = row.astype(np.uint8)
        elif ftype == 1:  # Sub
            row = np.frombuffer(line, dtype=np.uint8).astype(np.int32)
            arr = np.zeros(stride, dtype=np.int32)
            for c in range(bpp):
                arr[c::bpp] = np.cumsum(row[c::bpp]) & 0xFF
            row = arr.astype(np.uint8)
        else:  # Average(3) / Paeth(4)：非线性预测，逐字节回放
            cur = bytearray(stride)
            if ftype == 3:
                for i in range(stride):
                    left = cur[i - bpp] if i >= bpp else 0
                    up = prev[i]
                    cur[i] = (line[i] + ((left + up) >> 1)) & 0xFF
            elif ftype == 4:
                up_left = 0
                for i in range(stride):
                    left = cur[i - bpp] if i >= bpp else 0
                    up = prev[i]
                    up_left = prev[i - bpp] if i >= bpp else 0
                    p = left + up - up_left
                    pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                    if pa <= pb and pa <= pc:
                        pred = left
                    elif pb <= pc:
                        pred = up
                    else:
                        pred = up_left
                    cur[i] = (line[i] + pred) & 0xFF
            else:
                raise PNGError(f"unknown PNG filter type {ftype}")
            row = np.frombuffer(bytes(cur), dtype=np.uint8)
        out[y] = row
        prev = out[y]
    return out


def decode(data: bytes) -> np.ndarray:
    """PNG 字节流 -> (H, W, 3) uint8 RGB。"""
    if not data.startswith(PNG_SIGNATURE):
        raise PNGError("not a PNG file")
    ihdr = None
    palette = None
    trns = None
    idat = bytearray()
    for ctype, body in _chunks(data):
        if ctype == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif ctype == b"PLTE":
            palette = body
        elif ctype == b"tRNS":
            trns = body
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
    if ihdr is None:
        raise PNGError("missing IHDR")
    width, height, depth, color_type, _comp, _filt, interlace = ihdr
    if interlace != 0:
        raise PNGError("interlaced PNG (Adam7) is not supported")
    if depth not in (8, 16):
        raise PNGError(f"unsupported bit depth {depth}")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise PNGError(f"unsupported color type {color_type}")
    bpp = max(1, channels * depth // 8)
    stride = width * channels * depth // 8
    raw = zlib.decompress(bytes(idat))
    if len(raw) < height * (stride + 1):
        raise PNGError("PNG data shorter than expected")
    pixels = _unfilter(raw, width, height, bpp, stride)
    if depth == 16:
        pixels = pixels.reshape(height, width * channels, 2)[:, :, 0]  # 取高字节
        pixels = pixels.reshape(height, width * channels)
    if color_type == 3:
        if palette is None:
            raise PNGError("palette PNG without PLTE")
        idx = pixels.reshape(height, width)
        pal = np.frombuffer(palette, dtype=np.uint8).reshape(-1, 3)
        if idx.max(initial=0) >= len(pal):
            raise PNGError("palette index out of range")
        rgb = pal[idx].astype(np.uint8)
        if trns:
            alpha = np.full((height, width), 255, dtype=np.uint8)
            for i, a in enumerate(trns[: len(pal)]):
                alpha[idx == i] = a
        else:
            alpha = None
        return _composite_over_white(rgb, alpha)
    arr = pixels.reshape(height, width * channels)
    if color_type == 0:
        gray = arr.reshape(height, width)
        return np.stack([gray] * 3, axis=-1)
    if color_type == 4:
        gray = arr[:, 0::2]
        alpha = arr[:, 1::2]
        rgb = np.stack([gray] * 3, axis=-1)
        return _composite_over_white(rgb, alpha)
    if color_type == 2:
        return arr.reshape(height, width, 3).copy()
    rgba = arr.reshape(height, width, 4)
    return _composite_over_white(rgba[:, :, :3], rgba[:, :, 3])


def _composite_over_white(rgb: np.ndarray, alpha: np.ndarray | None) -> np.ndarray:
    if alpha is None:
        return np.ascontiguousarray(rgb, dtype=np.uint8)
    a = alpha.astype(np.float32)[..., None] / 255.0
    out = rgb.astype(np.float32) * a + 255.0 * (1.0 - a)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def _chunk(ctype: bytes, body: bytes) -> bytes:
    return (
        struct.pack(">I", len(body))
        + ctype
        + body
        + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF)
    )


def encode(rgb: np.ndarray, level: int = 6) -> bytes:
    """(H, W, 3) uint8 RGB -> PNG 字节流。"""
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise PNGError("encode expects (H, W, 3) RGB image")
    rgb = np.ascontiguousarray(np.clip(rgb, 0, 255).astype(np.uint8))
    h, w = rgb.shape[:2]
    stride = w * 3
    lines = np.concatenate(
        [np.zeros((h, 1), dtype=np.uint8), rgb.reshape(h, stride)], axis=1
    )  # 每行前置 filter=None
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(lines.tobytes(), level))
        + _chunk(b"IEND", b"")
    )


def size_of(data: bytes) -> Tuple[int, int]:
    """只读 IHDR 拿尺寸，不整图解码。"""
    if not data.startswith(PNG_SIGNATURE):
        raise PNGError("not a PNG file")
    width, height = struct.unpack(">II", data[16:24])
    return width, height
