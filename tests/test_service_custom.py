# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""服务层：自定义嵌入文本（v2）闭环测试。"""

import tempfile
import unittest
from pathlib import Path

from invismark.config import Settings
from invismark.service import Service, ServiceError

from invismark.core import image as imio
from tests.support import synth


class CustomTextServiceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.settings = Settings(
            db_path=str(Path(self.tmp.name) / "svc.db"),
            data_dir=str(Path(self.tmp.name) / "data"),
            base_long_edge=800,
        )
        self.service = Service(self.settings)
        self.img = imio.save_bytes(synth(800, 600, seed=5))

    def tearDown(self):
        self.service.store.close()
        self.tmp.cleanup()

    def test_embed_extract_custom_text(self):
        out = self.service.embed(self.img, user="carol", custom_text="内部-2026")
        self.assertEqual(out.payload["custom_text"], "内部-2026")
        self.assertEqual(out.payload["user_index"], 0)

        got = self.service.extract(out.image, requester="carol")
        self.assertTrue(got["found"])
        self.assertEqual(got["custom_text"], "内部-2026")
        self.assertEqual(got["trace_id"], out.payload["trace_id"])

    def test_rejects_too_long_custom_text(self):
        with self.assertRaises(ServiceError) as ctx:
            self.service.embed(self.img, custom_text="这个文本肯定超过十三个字节了")
        self.assertEqual(ctx.exception.code, "bad_custom_text")


if __name__ == "__main__":
    unittest.main()
