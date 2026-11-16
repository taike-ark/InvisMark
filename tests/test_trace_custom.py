# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""自定义文本追溯码（v2）测试。"""

import unittest

from invismark.core import trace


class CustomTraceTest(unittest.TestCase):
    def test_roundtrip_ascii(self):
        code = trace.TraceCode.new_custom("ABC-2026")
        raw = code.to_bytes()
        self.assertEqual(len(raw), 24)
        self.assertEqual(raw[0], trace.VERSION_CUSTOM)
        back = trace.TraceCode.from_bytes(raw)
        self.assertTrue(back.is_custom)
        self.assertEqual(back.custom_text, "ABC-2026")
        self.assertEqual(back.version, trace.VERSION_CUSTOM)

    def test_roundtrip_cjk(self):
        code = trace.TraceCode.new_custom("张三-内部")
        back = trace.TraceCode.from_bytes(code.to_bytes())
        self.assertEqual(back.custom_text, "张三-内部")

    def test_limit_13_bytes(self):
        trace.TraceCode.new_custom("abcdefghijklm")
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.new_custom("abcdefghijklmn")
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.new_custom("四汉字超了")

    def test_rejects_empty(self):
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.new_custom("   ")

    def test_serial_and_time_survive(self):
        from datetime import datetime, timezone

        code = trace.TraceCode.new_custom(
            "SN-001", embedded_at=datetime(2026, 11, 16, 7, 30, tzinfo=timezone.utc), serial=1234
        )
        back = trace.TraceCode.from_bytes(code.to_bytes())
        self.assertEqual(back.serial, 1234)
        self.assertEqual(back.embedded_at.hour, 7)
        self.assertEqual(back.embedded_at.minute, 30)

    def test_crc_detects_corruption(self):
        raw = bytearray(trace.TraceCode.new_custom("HELLO").to_bytes())
        raw[3] ^= 0x01
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.from_bytes(bytes(raw))

    def test_v1_still_parses(self):
        v1 = trace.TraceCode.new("F13241", 7)
        back = trace.TraceCode.from_bytes(v1.to_bytes())
        self.assertFalse(back.is_custom)
        self.assertEqual(back.resource_code, "F13241")
        self.assertEqual(back.version, 1)


if __name__ == "__main__":
    unittest.main()
