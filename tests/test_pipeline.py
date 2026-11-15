# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""端到端管线测试：嵌入 → 画质 → 各类二次处理后的检出。"""

import unittest

import numpy as np

from invismark.core import image as imio
from invismark.core import pipeline, trace

from tests.support import add_noise, blur3, jitter_brightness, scale, synth

BASE = 800
SEED = 20260115
CODE = trace.TraceCode.new("F13241", 7)


def _embed(img, code=CODE, seed=SEED):
    return pipeline.embed(img, code, seed, base_long_edge=BASE)


class PipelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = synth(800, 600, seed=0)
        cls.res = _embed(cls.src)

    def test_quality_budget(self):
        self.assertGreaterEqual(self.res.psnr, 40.0, f"PSNR too low: {self.res.psnr}")
        self.assertGreaterEqual(self.res.ssim, 0.9, f"SSIM too low: {self.res.ssim}")
        self.assertEqual(self.res.trace_id, CODE.hex)
        self.assertGreaterEqual(self.res.blocks_per_bit, 8)

    def test_clean_roundtrip(self):
        got = pipeline.extract(self.res.image, SEED, base_long_edge=BASE)
        self.assertTrue(got.found)
        self.assertEqual(got.trace_id, CODE.hex)
        self.assertLessEqual(got.corrected_bytes, 20)  # 低分辨率下允许少量纠错
        self.assertEqual(got.trace.resource_code, "F13241")
        self.assertEqual(got.trace.user_index, 7)

    def test_survives_png_reencode(self):
        data = imio.save_bytes(self.res.image)
        got = pipeline.extract(imio.load_bytes(data), SEED, base_long_edge=BASE)
        self.assertTrue(got.found)

    def test_survives_noise(self):
        for sigma in (1.0, 3.0):
            got = pipeline.extract(add_noise(self.res.image, sigma), SEED, base_long_edge=BASE)
            self.assertTrue(got.found, f"noise sigma={sigma} lost the watermark")

    def test_survives_rescale(self):
        for factor in (0.5, 0.75, 2.0):
            got = pipeline.extract(scale(self.res.image, factor), SEED, base_long_edge=BASE)
            self.assertTrue(got.found, f"rescaling x{factor} lost the watermark")

    def test_survives_brightness_and_blur(self):
        for label, attacked in (
            ("brightness", jitter_brightness(self.res.image)),
            ("blur", blur3(self.res.image)),
        ):
            got = pipeline.extract(attacked, SEED, base_long_edge=BASE)
            self.assertTrue(got.found, f"{label} lost the watermark")

    def test_wrong_seed_rejects(self):
        got = pipeline.extract(self.res.image, SEED + 1, base_long_edge=BASE)
        self.assertFalse(got.found)

    def test_unmarked_image_not_found(self):
        other = synth(800, 600, seed=99)
        got = pipeline.extract(other, SEED, base_long_edge=BASE)
        self.assertFalse(got.found)

    def test_min_size_enforced(self):
        with self.assertRaises(pipeline.InvisMarkError):
            _embed(synth(320, 240))

    def test_rejects_bad_arguments(self):
        with self.assertRaises(pipeline.InvisMarkError):
            pipeline.embed(np.zeros((600, 800), np.uint8), CODE, SEED)  # 灰度图不是 RGB
        with self.assertRaises(pipeline.InvisMarkError):
            pipeline.embed(self.src, CODE, SEED, alpha=0.0, base_long_edge=BASE)

    def test_flat_image_does_not_crash_or_mismatch(self):
        flat = np.full((600, 800, 3), 190, np.uint8)
        res = _embed(flat)
        got = pipeline.extract(res.image, SEED, base_long_edge=BASE)
        # 极端纯色图本就不保证检出，但不允许抛异常或解码成别的码
        if got.found:
            self.assertEqual(got.trace_id, CODE.hex)

    def test_distinct_codes_roundtrip(self):
        codes = [
            trace.TraceCode.new("AAAAAA", 1),
            trace.TraceCode.new("ZZZZZZ", 65535),
            trace.TraceCode.new("000001", 300),
        ]
        for code in codes:
            res = _embed(self.src, code=code)
            got = pipeline.extract(res.image, SEED, base_long_edge=BASE)
            self.assertTrue(got.found)
            self.assertEqual(got.trace_id, code.hex)

    def test_file_helpers(self):
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "in.png"
            dst = Path(tmp) / "out.png"
            imio.save(src, self.src)
            res = pipeline.embed_file(str(src), str(dst), CODE, SEED, base_long_edge=BASE)
            self.assertTrue(dst.exists())
            got = pipeline.extract_file(str(dst), SEED, base_long_edge=BASE)
            self.assertTrue(got.found)
            self.assertEqual(got.trace_id, res.trace_id)


if __name__ == "__main__":
    unittest.main()
