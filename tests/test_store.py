# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""SQLite 存储与审计哈希链测试。"""

import tempfile
import unittest
from pathlib import Path

from invismark.core import trace
from invismark.store import Store, StoreError


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(str(Path(self.tmp.name) / "test.db"))
        self.tenant = self.store.ensure_tenant("acme")

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_tenant_and_user_index_allocation(self):
        self.assertEqual(self.store.ensure_tenant("acme"), self.tenant)
        _, idx1 = self.store.ensure_user(self.tenant, "alice")
        _, idx2 = self.store.ensure_user(self.tenant, "bob")
        _, idx1_again = self.store.ensure_user(self.tenant, "alice")
        self.assertEqual((idx1, idx2), (1, 2))
        self.assertEqual(idx1_again, idx1)

    def test_record_and_lookup_trace(self):
        code = trace.TraceCode.new("F13241", 2)
        uid, _ = self.store.ensure_user(self.tenant, "alice")
        asset = self.store.record_embed(
            code,
            tenant_id=self.tenant,
            user_id=uid,
            sha256_orig="a" * 64,
            sha256_wm="b" * 64,
            uri_wm="data/x.png",
            width=1200,
            height=800,
            psnr=48.2,
            ssim=0.99,
        )
        info = self.store.get_trace(code.hex.lower())
        self.assertIsNotNone(info)
        self.assertEqual(info["asset_id"], asset)
        self.assertEqual(info["resource_code"], "F13241")
        self.assertEqual(info["external_id"], "alice")
        self.assertIsNone(self.store.get_trace("00" * 24))

    def test_audit_chain_is_valid_and_detects_tamper(self):
        self.store.append_audit("x", "tester", "target-1")
        self.store.append_audit("y", "tester", "target-2")
        ok, bad = self.store.verify_chain()
        self.assertTrue(ok)
        self.assertIsNone(bad)
        conn = self.store._conn()
        conn.execute("UPDATE audit_logs SET target='hacked' WHERE id=2")
        conn.commit()
        ok, bad = self.store.verify_chain()
        self.assertFalse(ok)
        self.assertEqual(bad, 2)

    def test_count_month(self):
        code = trace.TraceCode.new("F13241", 1)
        self.store.record_embed(
            code, tenant_id=self.tenant, user_id=None,
            sha256_orig="", sha256_wm="", uri_wm="", width=0, height=0,
            psnr=0.0, ssim=0.0,
        )
        self.assertEqual(self.store.count_month(self.tenant), 1)

    def test_export_rows_and_unknown_table(self):
        self.assertGreaterEqual(len(self.store.export_rows("tenants")), 1)
        with self.assertRaises(StoreError):
            self.store.export_rows("sqlite_master")


if __name__ == "__main__":
    unittest.main()
