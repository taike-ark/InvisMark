# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""服务层 + 证据包 + HTTP API + CLI 的集成测试。"""

import base64
import io
import json
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

from invismark.api.app import ApiApp, serve_in_thread
from invismark.config import Settings
from invismark.service import Service, ServiceError
from invismark.store import Store

from tests.support import synth
from invismark.core import image as imio

REPO = Path(__file__).resolve().parents[1]


class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.settings = Settings(
            db_path=str(Path(self.tmp.name) / "svc.db"),
            data_dir=str(Path(self.tmp.name) / "data"),
            base_long_edge=800,
        )
        self.service = Service(self.settings)
        self.img = imio.save_bytes(synth(800, 600, seed=3))

    def tearDown(self):
        self.service.store.close()
        self.tmp.cleanup()

    def test_embed_extract_trace_flow(self):
        out = self.service.embed(self.img, user="alice", resource_code="F13241")
        payload = out.payload
        self.assertEqual(payload["resource_code"], "F13241")
        self.assertEqual(payload["user_index"], 1)
        self.assertGreaterEqual(payload["quality"]["psnr"], 40)

        got = self.service.extract(out.image, requester="tester")
        self.assertTrue(got["found"])
        self.assertEqual(got["trace_id"], payload["trace_id"])
        self.assertTrue(got["registered"])
        self.assertEqual(got["user"]["external_id"], "alice")

        info = self.service.trace_info(payload["trace_id"])
        self.assertEqual(info["resource_code"], "F13241")
        self.assertEqual(info["size"], {"width": 800, "height": 600})
        self.assertTrue(self.service.verify_chain()["ok"])

    def test_extract_unmarked_image_is_fail_open(self):
        got = self.service.extract(imio.save_bytes(synth(800, 600, seed=42)))
        self.assertFalse(got["found"])
        self.assertIn("reason", got)

    def test_rejects_tiny_image(self):
        small = imio.save_bytes(synth(320, 240))
        with self.assertRaises(ServiceError) as ctx:
            self.service.embed(small)
        self.assertEqual(ctx.exception.status, 422)

    def test_rejects_undecodable(self):
        with self.assertRaises(ServiceError) as ctx:
            self.service.embed(b"not an image")
        self.assertEqual(ctx.exception.code, "undecodable")

    def test_reserve_offline_codes(self):
        codes = self.service.reserve(5)
        self.assertEqual(len(codes), 5)
        for code in codes:
            self.assertIsNotNone(self.service.trace_info(code))

    def test_evidence_pack_verifies_offshelf(self):
        out = self.service.embed(self.img, user="bob", resource_code="AAAAAA")
        blob = self.service.evidence_zip(
            out.payload["trace_id"], original_bytes=self.img, watermarked_bytes=out.image
        )
        with zipfile.ZipFile(io.BytesIO(blob)) as zf:
            names = set(zf.namelist())
            self.assertIn("manifest.json", names)
            self.assertIn("verify.py", names)
            self.assertIn("chain.jsonl", names)
            zf.extractall(self.tmp.name)
        script = Path(self.tmp.name) / "verify.py"
        proc = subprocess.run(
            [sys.executable, str(script)], capture_output=True, text=True, cwd=self.tmp.name
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("PASS", proc.stdout)

    def test_evidence_tamper_detected(self):
        out = self.service.embed(self.img)
        blob = self.service.evidence_zip(out.payload["trace_id"], watermarked_bytes=out.image)
        with zipfile.ZipFile(io.BytesIO(blob)) as zf:
            zf.extractall(self.tmp.name)
        target = Path(self.tmp.name) / "watermarked.png"
        data = bytearray(target.read_bytes())
        data[200] ^= 0xFF
        target.write_bytes(bytes(data))
        proc = subprocess.run(
            [sys.executable, str(Path(self.tmp.name) / "verify.py")],
            capture_output=True, text=True, cwd=self.tmp.name,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("FAIL", proc.stdout)

    def test_quota_reported(self):
        q = self.service.quota()
        self.assertEqual(q["used"], 0)
        self.assertGreater(q["limit"], 0)

    def test_tenant_isolation(self):
        a = self.service.embed(self.img, tenant="tenant-a", user="a")
        b = self.service.embed(self.img, tenant="tenant-b", user="b")
        self.assertNotEqual(a.payload["trace_id"], b.payload["trace_id"])


class ApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        settings = Settings(
            db_path=str(Path(cls.tmp.name) / "api.db"),
            data_dir=str(Path(cls.tmp.name) / "data"),
            base_long_edge=800,
        )
        cls.app = ApiApp(settings)
        cls.server, cls.thread, cls.url = serve_in_thread("127.0.0.1", 0, cls.app)
        cls.img = imio.save_bytes(synth(800, 600, seed=5))

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.app.service.store.close()
        cls.tmp.cleanup()

    def _get(self, path):
        with urllib.request.urlopen(self.url + path, timeout=30) as resp:
            return resp.status, json.loads(resp.read())

    def _post(self, path, data, ctype="image/png"):
        req = urllib.request.Request(
            self.url + path, data=data, headers={"content-type": ctype}, method="POST"
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, json.loads(resp.read())

    def test_health(self):
        status, body = self._get("/healthz")
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])

    def test_openapi(self):
        status, body = self._get("/openapi.json")
        self.assertEqual(status, 200)
        self.assertIn("/v1/embed", body["paths"])

    def test_embed_extract_cycle(self):
        status, body = self._post("/v1/embed?user=api-user&resource_code=F13241", self.img)
        self.assertEqual(status, 201)
        wm = base64.b64decode(body["image_base64"])
        status, got = self._post("/v1/extract", wm)
        self.assertEqual(status, 200)
        self.assertTrue(got["found"])
        self.assertEqual(got["trace_id"], body["trace_id"])

    def test_unknown_route_and_trace(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._get("/v1/nope")
        self.assertEqual(ctx.exception.code, 404)
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._get("/v1/traces/" + "00" * 24)
        self.assertEqual(ctx.exception.code, 404)

    def test_multipart_upload(self):
        boundary = "X-BOUNDARY"
        body = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.png\"\r\n"
            f"Content-Type: image/png\r\n\r\n".encode()
            + self.img
            + f"\r\n--{boundary}--\r\n".encode()
        )
        status, out = self._post(
            "/v1/embed?user=mp", body, ctype=f"multipart/form-data; boundary={boundary}"
        )
        self.assertEqual(status, 201)
        self.assertTrue(out["trace_id"])


class CliTest(unittest.TestCase):
    def test_demo_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = subprocess.run(
                [sys.executable, "-m", "invismark", "demo", "--out", tmp],
                capture_output=True, text=True, cwd=REPO, timeout=300,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            data = json.loads(proc.stdout)
            self.assertTrue(data["found"])
            self.assertTrue((Path(tmp) / "demo-watermarked.png").exists())

    def test_verify_chain_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = str(Path(tmp) / "cli.db")
            proc = subprocess.run(
                [sys.executable, "-m", "invismark", "verify", "--db", db],
                capture_output=True, text=True, cwd=REPO, timeout=120,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertTrue(json.loads(proc.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
