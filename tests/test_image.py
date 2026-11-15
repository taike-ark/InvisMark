# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""纯 Python PNG 编解码与图像工具测试。"""

import unittest
import zlib

import numpy as np

from invismark.core import image as imio
from invismark.core import png

from tests.support import scale, synth


def _make_png(width, height, color_type, channels, rows, palette=None, depth=8):
    """手工拼一个最小 PNG，用于覆盖灰度/调色板/RGBA 解码分支。"""

    def chunk(ctype, body):
        return (
            len(body).to_bytes(4, "big")
            + ctype
            + body
            + zlib.crc32(ctype + body).to_bytes(4, "big")
        )

    ihdr = (
        width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
        + bytes([depth, color_type, 0, 0, 0])
    )
    raw = b"".join(b"\x00" + row for row in rows)
    out = png.PNG_SIGNATURE + chunk(b"IHDR", ihdr)
    if palette:
        out += chunk(b"PLTE", palette)
    return out + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class PNGTest(unittest.TestCase):
    def test_rgb_roundtrip(self):
        img = synth(64, 48)
        data = png.encode(img)
        back = png.decode(data)
        self.assertTrue(np.array_equal(img, back))
        self.assertEqual(png.size_of(data), (64, 48))

    def test_grayscale(self):
        rows = [bytes([y * 4 % 256] * 32) for y in range(16)]
        data = _make_png(32, 16, 0, 1, rows)
        img = png.decode(data)
        self.assertEqual(img.shape, (16, 32, 3))
        self.assertTrue((img[..., 0] == img[..., 2]).all())

    def test_rgba_composited_over_white(self):
        rows = [bytes([0, 0, 0, 0] * 16) for _ in range(8)]  # 全透明
        data = _make_png(16, 8, 6, 4, rows)
        img = png.decode(data)
        self.assertTrue((img == 255).all())

    def test_palette(self):
        rows = [bytes([0, 1] * 8) for _ in range(8)]
        palette = bytes([255, 0, 0, 0, 0, 255])
        data = _make_png(16, 8, 3, 1, rows, palette=palette)
        img = png.decode(data)
        self.assertTrue((img[0, 0] == [255, 0, 0]).all())
        self.assertTrue((img[0, 1] == [0, 0, 255]).all())

    def test_rejects_garbage(self):
        with self.assertRaises(png.PNGError):
            png.decode(b"not a png")


class ImageToolsTest(unittest.TestCase):
    def test_resize_identity_and_shape(self):
        img = synth(64, 48)
        same = imio.resize(img, 48, 64)
        self.assertEqual(same.shape, img.shape)
        small = imio.resize(img, 24, 32)
        self.assertEqual(small.shape, (24, 32, 3))
        self.assertEqual(small.dtype, np.uint8)

    def test_fit_long_edge(self):
        h, w = imio.fit_long_edge(600, 800, 800, multiple=16)
        self.assertEqual(max(h, w), 800)          # 长边对齐到目标
        self.assertEqual(h % 16, 0)
        self.assertEqual(w % 16, 0)
        self.assertAlmostEqual(h / w, 600 / 800, delta=0.04)  # 近似保持宽高比

        h2, w2 = imio.fit_long_edge(300, 400, 800, multiple=16)
        self.assertEqual(w2, 800)                            # 长边从 400 放大到 800
        self.assertAlmostEqual(h2 / w2, 300 / 400, delta=0.02)
        self.assertEqual(h2 % 16, 0)

    def test_ycbcr_roundtrip_is_lossless_on_uint8(self):
        img = synth(64, 48)
        y, cb, cr = imio.to_ycbcr(img)
        back = imio.from_ycbcr(y, cb, cr)
        self.assertTrue(np.array_equal(img, back))

    def test_psnr_and_ssim(self):
        img = synth(64, 48)
        self.assertEqual(imio.psnr(img, img), float("inf"))
        noisy = np.clip(img.astype(np.float32) + 5, 0, 255).astype(np.uint8)
        self.assertGreater(imio.psnr(img, noisy), 30)
        self.assertLess(imio.psnr(img, noisy), 40)
        self.assertGreater(imio.ssim(img, noisy), 0.9)
        self.assertLessEqual(imio.ssim(img, noisy), 1.0)

    def test_scale_down_keeps_aspect(self):
        img = synth(160, 120)
        out = scale(img, 0.5)
        self.assertEqual(out.shape[:2], (60, 80))


if __name__ == "__main__":
    unittest.main()
