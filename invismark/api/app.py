# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""零依赖 HTTP API（stdlib http.server）：embed / extract / trace / evidence / reserve。

为什么不用 FastAPI：参考实现的目标是「任何装了 Python 的机器都能跑」，
私有化/内网/断网场景下少一个依赖就少一类故障。生产环境可在 service.py 外
再套 FastAPI/uvicorn，业务层不用改。
"""

from __future__ import annotations

import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable
from urllib.parse import parse_qs, urlparse

from ..config import Settings
from ..service import Service, ServiceError

MAX_BODY = 40 * 1024 * 1024  # 40 MB


# ---------------------------------------------------------------- multipart


def parse_multipart(body: bytes, content_type: str) -> tuple[dict[str, bytes], dict[str, str]]:
    """极简 multipart/form-data 解析：返回 (文件字段, 文本字段)。"""
    m = re.search(r"boundary=([^\s;]+)", content_type or "")
    if not m:
        raise ServiceError("multipart boundary missing", code="bad_request")
    boundary = b"--" + m.group(1).strip('"').encode()
    files: dict[str, bytes] = {}
    fields: dict[str, str] = {}
    for part in body.split(boundary):
        if not part.strip() or part.strip() == b"--":
            continue
        if b"\r\n\r\n" not in part:
            continue
        raw_headers, data = part.split(b"\r\n\r\n", 1)
        data = data.rstrip(b"\r\n")
        headers = raw_headers.decode("utf-8", "replace")
        name_m = re.search(r'name="([^"]+)"', headers)
        if not name_m:
            continue
        name = name_m.group(1)
        if re.search(r'filename="', headers):
            files[name] = data
        else:
            fields[name] = data.decode("utf-8", "replace")
    return files, fields


# ---------------------------------------------------------------- handler


class ApiApp:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or Settings()
        self.service = Service(self.settings)

    # 路由表：(方法, 正则) -> handler(app, match, body, headers)
    def dispatch(self, method: str, path: str, body: bytes, headers: dict[str, str]):
        """返回 (status, content_type, payload_bytes)。"""
        try:
            return self._dispatch(method, path, body, headers)
        except ServiceError as exc:
            return exc.status, "application/json", self._json({"error": exc.code, "message": str(exc)})
        except Exception as exc:  # pragma: no cover - 兜底，避免服务端直接崩
            return 500, "application/json", self._json({"error": "internal", "message": str(exc)})

    def _dispatch(self, method: str, path: str, body: bytes, headers: dict[str, str]):
        parsed = urlparse(path)
        route = parsed.path
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
        if method == "GET" and route in ("/healthz", "/health"):
            return 200, "application/json", self._json({"ok": True, "version": "0.1.0"})
        if method == "GET" and route == "/openapi.json":
            return 200, "application/json", self._json(OPENAPI)
        if method == "GET" and route == "/v1/quota":
            return 200, "application/json", self._json(self.service.quota(query.get("tenant")))
        if method == "POST" and route == "/v1/embed":
            return self._embed(body, headers, query)
        if method == "POST" and route == "/v1/extract":
            return self._extract(body, headers)
        if method == "GET" and route.startswith("/v1/traces/"):
            return 200, "application/json", self._json(
                self.service.trace_info(route.rsplit("/", 1)[-1])
            )
        if method == "POST" and route == "/v1/traces/reserve":
            data = json.loads(body or b"{}")
            codes = self.service.reserve(int(data.get("count", 1)), tenant=data.get("tenant"))
            return 201, "application/json", self._json({"trace_ids": codes})
        if method == "POST" and route == "/v1/reports":
            data = json.loads(body or b"{}")
            blob = self.service.evidence_zip(data["trace_id"], requester=data.get("requester", ""))
            return 200, "application/zip", blob
        if method == "GET" and route == "/v1/chain/verify":
            return 200, "application/json", self._json(self.service.verify_chain())
        raise ServiceError(f"no route: {method} {route}", code="not_found", status=404)

    def _embed(self, body: bytes, headers: dict[str, str], query: dict[str, str]):
        ctype = headers.get("content-type", "")
        if "multipart/form-data" in ctype:
            files, fields = parse_multipart(body, ctype)
            if "file" not in files:
                raise ServiceError("multipart field 'file' is required", code="bad_request")
            image_bytes = files["file"]
            user = fields.get("user", query.get("user", "anonymous"))
            resource = fields.get("resource_code", query.get("resource_code", ""))
            custom_text = fields.get("custom_text", query.get("custom_text", ""))
        else:
            image_bytes = body
            user = query.get("user", "anonymous")
            resource = query.get("resource_code", "")
            custom_text = query.get("custom_text", "")
        if not image_bytes:
            raise ServiceError("empty image body", code="bad_request")
        outcome = self.service.embed(
            image_bytes,
            tenant=query.get("tenant"),
            user=user,
            resource_code=resource,
            custom_text=custom_text,
        )
        accept = headers.get("accept", "")
        if "application/json" in accept and "image" not in accept:
            return 201, "application/json", self._json(outcome.payload)
        # 默认返回 JSON + base64 成图，方便无文件系统的客户端一次拿全
        import base64

        payload = dict(outcome.payload)
        payload["image_base64"] = base64.b64encode(outcome.image).decode("ascii")
        payload["filename"] = outcome.filename
        return 201, "application/json", self._json(payload)

    def _extract(self, body: bytes, headers: dict[str, str]):
        ctype = headers.get("content-type", "")
        if "multipart/form-data" in ctype:
            files, _fields = parse_multipart(body, ctype)
            if "file" not in files:
                raise ServiceError("multipart field 'file' is required", code="bad_request")
            image_bytes = files["file"]
        else:
            image_bytes = body
        if not image_bytes:
            raise ServiceError("empty image body", code="bad_request")
        return 200, "application/json", self._json(self.service.extract(image_bytes))

    @staticmethod
    def _json(obj) -> bytes:
        return json.dumps(obj, ensure_ascii=False).encode("utf-8")


class _Handler(BaseHTTPRequestHandler):
    app: ApiApp  # 由 make_server 注入

    server_version = "InvisMark/0.1"

    def log_message(self, fmt, *args):  # 静音，交给调用方日志
        return

    def _read_body(self) -> bytes:
        length = int(self.headers.get("content-length") or 0)
        if length > MAX_BODY:
            raise ServiceError("payload too large", code="too_large", status=413)
        return self.rfile.read(length) if length else b""

    def _run(self, method: str) -> None:
        try:
            body = self._read_body()
            headers = {k.lower(): v for k, v in self.headers.items()}
            status, ctype, payload = self.app.dispatch(method, self.path, body, headers)
        except ServiceError as exc:
            status, ctype, payload = exc.status, "application/json", json.dumps(
                {"error": exc.code, "message": str(exc)}
            ).encode("utf-8")
        except Exception as exc:  # pragma: no cover
            status, ctype, payload = 500, "application/json", json.dumps(
                {"error": "internal", "message": str(exc)}
            ).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(payload)))
        self.send_header("access-control-allow-origin", "*")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):  # noqa: N802
        self._run("GET")

    def do_POST(self):  # noqa: N802
        self._run("POST")

    def do_OPTIONS(self):  # noqa: N802
        self.send_response(204)
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-headers", "content-type")
        self.send_header("access-control-allow-methods", "GET,POST,OPTIONS")
        self.end_headers()


def make_server(host: str, port: int, app: ApiApp | None = None) -> ThreadingHTTPServer:
    app = app or ApiApp()
    handler = type("BoundHandler", (_Handler,), {"app": app})
    server = ThreadingHTTPServer((host, port), handler)
    server.daemon_threads = True
    return server


def serve(host: str = "127.0.0.1", port: int = 8000, settings: Settings | None = None) -> None:
    app = ApiApp(settings)
    server = make_server(host, port, app)
    print(f"invisMark API listening on http://{host}:{port}  (db={app.settings.db_path})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def serve_in_thread(host: str = "127.0.0.1", port: int = 0, app: ApiApp | None = None):
    """测试用：后台线程起服务，返回 (server, thread, base_url)。"""
    server = make_server(host, port, app)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread, f"http://{host}:{server.server_address[1]}"


OPENAPI = {
    "openapi": "3.0.3",
    "info": {"title": "隐迹 InvisMark API", "version": "0.1.0"},
    "paths": {
        "/v1/embed": {"post": {"summary": "单图嵌入，返回成图(base64) 与追溯码"}},
        "/v1/extract": {"post": {"summary": "单图提取追溯码（fail-open）"}},
        "/v1/traces/{trace_id}": {"get": {"summary": "追溯码详情"}},
        "/v1/traces/reserve": {"post": {"summary": "离线设备预分配 trace_id"}},
        "/v1/reports": {"post": {"summary": "生成证据包 ZIP"}},
        "/v1/quota": {"get": {"summary": "本月用量与配额"}},
        "/v1/chain/verify": {"get": {"summary": "校验审计哈希链"}},
    },
}
