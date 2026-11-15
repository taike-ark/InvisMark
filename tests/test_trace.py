# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""24 字节追溯码编解码测试。"""

import unittest
from datetime import datetime, timezone

from invismark.core import trace


class TraceCodeTest(unittest.TestCase):
    def test_roundtrip(self):
        code = trace.TraceCode.new(
            "F13241", 7, datetime(2026, 11, 15, 9, 20, tzinfo=timezone.utc), serial=42
        )
        raw = code.to_bytes()
        self.assertEqual(len(raw), 24)
        back = trace.TraceCode.from_bytes(raw)
        self.assertEqual(back.resource_code, "F13241")
        self.assertEqual(back.user_index, 7)
        self.assertEqual(back.serial, 42)
        self.assertEqual(back.embedded_at, code.embedded_at.replace(second=0, microsecond=0))
        self.assertEqual(back.hex, code.hex)

    def test_hex_helpers(self):
        code = trace.TraceCode.new("AB12", 1)
        self.assertEqual(len(code.hex), 48)
        self.assertEqual(trace.TraceCode.from_hex(code.hex.lower()).hex, code.hex)
        self.assertEqual(code.to_dict()["resource_code"], "00AB12")

    def test_hex_equivalence(self):
        code = trace.TraceCode.new("ZZZZZZ", 65535, serial=0xFFFFFFFF)
        self.assertEqual(trace.TraceCode.from_bytes(code.to_bytes()).hex, code.hex)

    def test_crc_detects_corruption(self):
        raw = bytearray(trace.TraceCode.new("F13241", 7).to_bytes())
        raw[5] ^= 0x01
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.from_bytes(bytes(raw))

    def test_reserved_bytes_must_be_zero(self):
        raw = bytearray(trace.TraceCode.new("F13241", 7).to_bytes())
        raw[22] = 1
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.from_bytes(bytes(raw))

    def test_version_checked(self):
        raw = bytearray(trace.TraceCode.new("F13241", 7).to_bytes())
        raw[0] = 9
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.from_bytes(bytes(raw))

    def test_invalid_inputs(self):
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.new("TOO-LONG-CODE", 1)
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.new("F13241", -1)
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.new("F1324$", 1)
        with self.assertRaises(trace.TraceFormatError):
            trace.TraceCode.from_bytes(b"\x01" * 10)

    def test_minute_precision(self):
        dt = datetime(2026, 1, 2, 3, 4, 59, 999000, tzinfo=timezone.utc)
        code = trace.TraceCode.new("F13241", 3, dt)
        back = trace.TraceCode.from_bytes(code.to_bytes())
        self.assertEqual(back.embedded_at.second, 0)
        self.assertEqual(back.embedded_at.minute, 4)


if __name__ == "__main__":
    unittest.main()
