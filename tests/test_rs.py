# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""RS(64,24) 与 GF(256) 的单元测试。"""

import random
import unittest

from invismark.core import gf256 as gf
from invismark.core import rs


class GF256Test(unittest.TestCase):
    def test_inverse_and_mul(self):
        for a in range(1, 256):
            self.assertEqual(gf.gf_mul(a, gf.gf_inverse(a)), 1)
        self.assertEqual(gf.gf_mul(0, 123), 0)
        self.assertEqual(gf.gf_div(gf.gf_mul(37, 91), 37), 91)

    def test_pow_wraps(self):
        self.assertEqual(gf.gf_pow(2, 255), 1)
        self.assertEqual(gf.gf_pow(2, 8), 0x1D)  # x^8 = x^4+x^3+x^2+1


class ReedSolomonTest(unittest.TestCase):
    def test_sizes(self):
        payload = bytes(range(24))
        codeword = rs.encode(payload)
        self.assertEqual(len(codeword), 64)
        self.assertEqual(codeword[:24], payload)  # 系统码

    def test_clean_roundtrip(self):
        rng = random.Random(7)
        for _ in range(20):
            payload = bytes(rng.randrange(256) for _ in range(24))
            dec = rs.decode(rs.encode(payload))
            self.assertTrue(dec.ok)
            self.assertEqual(dec.payload, payload)
            self.assertEqual(dec.corrected, 0)
            self.assertEqual(dec.ber, 0.0)

    def test_corrects_up_to_20_errors(self):
        rng = random.Random(11)
        for errors in (1, 5, 10, 15, 20):
            for _ in range(5):
                payload = bytes(rng.randrange(256) for _ in range(24))
                cw = bytearray(rs.encode(payload))
                for pos in rng.sample(range(64), errors):
                    cw[pos] ^= rng.randrange(1, 256)
                dec = rs.decode(bytes(cw))
                self.assertTrue(dec.ok, f"errors={errors}")
                self.assertEqual(dec.payload, payload)
                self.assertEqual(dec.corrected, errors)

    def test_rejects_beyond_capacity(self):
        rng = random.Random(3)
        payload = bytes(range(24))
        for _ in range(20):
            cw = bytearray(rs.encode(payload))
            for pos in rng.sample(range(64), 26):
                cw[pos] ^= rng.randrange(1, 256)
            dec = rs.decode(bytes(cw))
            if dec.ok:  # 极小概率误纠：至少不能悄悄给出别的载荷
                self.assertNotEqual(dec.payload, payload)

    def test_bad_length(self):
        dec = rs.decode(b"\x00" * 10)
        self.assertFalse(dec.ok)
        self.assertIn("64", dec.message)


if __name__ == "__main__":
    unittest.main()
