# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""SQLite 存储层（stdlib sqlite3，零第三方依赖）。

表结构与说明书 §9 对应，但为了可移植性把「用户索引映射 + 追溯 + 审计哈希链」放在
同一个库文件里，私有化部署时就是一个 ``.db`` 文件。

审计哈希链：每条 ``audit_logs`` 记录都带 ``prev_hash`` / ``this_hash``，
``this_hash = sha256(prev_hash || 规范化 JSON)``，任意一条被改都会在 ``verify_chain()``
里暴露——这是证据包「自证未被篡改」的基础。
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from .core import trace

SCHEMA = """
CREATE TABLE IF NOT EXISTS tenants (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    external_id TEXT NOT NULL,
    user_index INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE (tenant_id, external_id),
    UNIQUE (tenant_id, user_index)
);
CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    user_id TEXT,
    sha256_orig TEXT,
    sha256_wm TEXT,
    uri_wm TEXT,
    width INTEGER,
    height INTEGER,
    psnr REAL,
    ssim REAL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS traces (
    trace_id TEXT PRIMARY KEY,
    asset_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    resource_code TEXT NOT NULL,
    user_index INTEGER NOT NULL,
    embedded_at TEXT NOT NULL,
    seed_version INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS extracts (
    id TEXT PRIMARY KEY,
    trace_id TEXT,
    requester TEXT,
    found INTEGER NOT NULL,
    confidence REAL,
    ber REAL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    action TEXT NOT NULL,
    actor TEXT,
    target TEXT,
    prev_hash TEXT,
    this_hash TEXT NOT NULL,
    at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_traces_tenant ON traces (tenant_id);
CREATE INDEX IF NOT EXISTS idx_assets_tenant ON assets (tenant_id);
"""


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical(obj: dict) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class StoreError(RuntimeError):
    """存储层错误（租户不存在、追溯码未登记等）。"""


class Store:
    """线程安全的薄封装（每个线程独立连接）。"""

    def __init__(self, path: str | Path = "invismark.db"):
        self.path = str(path)
        self._local = threading.local()
        with self._conn() as conn:
            conn.executescript(SCHEMA)
            conn.commit()

    def _conn(self) -> sqlite3.Connection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = sqlite3.connect(self.path, timeout=30)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA foreign_keys=ON")
            self._local.conn = conn
        return conn

    def close(self) -> None:
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            conn.close()
            self._local.conn = None

    # ------------------------------------------------------------ 租户/用户

    def ensure_tenant(self, name: str) -> str:
        conn = self._conn()
        row = conn.execute("SELECT id FROM tenants WHERE name = ?", (name,)).fetchone()
        if row:
            return row["id"]
        tid = "t_" + uuid.uuid4().hex[:12]
        conn.execute(
            "INSERT INTO tenants (id, name, created_at) VALUES (?, ?, ?)", (tid, name, _utcnow())
        )
        conn.commit()
        self.append_audit("tenant.create", actor="system", target=tid)
        return tid

    def ensure_user(self, tenant_id: str, external_id: str) -> tuple[str, int]:
        """返回 (user_id, user_index)；user_index 是写进水印的整数，不含明文 PII。"""
        conn = self._conn()
        row = conn.execute(
            "SELECT id, user_index FROM users WHERE tenant_id = ? AND external_id = ?",
            (tenant_id, external_id),
        ).fetchone()
        if row:
            return row["id"], int(row["user_index"])
        row = conn.execute(
            "SELECT MAX(user_index) AS m FROM users WHERE tenant_id = ?", (tenant_id,)
        ).fetchone()
        next_index = (row["m"] or 0) + 1
        if next_index > 0xFFFF:
            raise StoreError("tenant user_index exhausted (max 65535)")
        uid = "u_" + uuid.uuid4().hex[:12]
        conn.execute(
            "INSERT INTO users (id, tenant_id, external_id, user_index, created_at) VALUES (?, ?, ?, ?, ?)",
            (uid, tenant_id, external_id, next_index, _utcnow()),
        )
        conn.commit()
        self.append_audit("user.create", actor=tenant_id, target=f"{tenant_id}/{external_id}")
        return uid, next_index

    # ------------------------------------------------------------ 资产/追溯

    def record_embed(
        self,
        trace_code: trace.TraceCode,
        *,
        tenant_id: str,
        user_id: str | None,
        sha256_orig: str,
        sha256_wm: str,
        uri_wm: str,
        width: int,
        height: int,
        psnr: float,
        ssim: float,
        seed_version: int = 1,
    ) -> str:
        conn = self._conn()
        asset_id = "as_" + uuid.uuid4().hex[:16]
        conn.execute(
            "INSERT INTO assets (id, tenant_id, user_id, sha256_orig, sha256_wm, uri_wm, width, height,"
            " psnr, ssim, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (asset_id, tenant_id, user_id, sha256_orig, sha256_wm, uri_wm,
             int(width), int(height), float(psnr), float(ssim), _utcnow()),
        )
        conn.execute(
            "INSERT INTO traces (trace_id, asset_id, tenant_id, resource_code, user_index, embedded_at,"
            " seed_version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                trace_code.hex,
                asset_id,
                tenant_id,
                trace_code.resource_code,
                trace_code.user_index,
                trace_code.embedded_at.isoformat(),
                int(seed_version),
                _utcnow(),
            ),
        )
        conn.commit()
        self.append_audit("embed", actor=tenant_id, target=trace_code.hex)
        return asset_id

    def get_trace(self, trace_id: str) -> dict | None:
        conn = self._conn()
        row = conn.execute(
            "SELECT t.*, a.sha256_orig, a.sha256_wm, a.width, a.height, a.psnr, a.ssim,"
            " u.external_id, u.id AS user_id"
            " FROM traces t LEFT JOIN assets a ON a.id = t.asset_id"
            " LEFT JOIN users u ON u.id = a.user_id WHERE t.trace_id = ?",
            (trace_id.upper(),),
        ).fetchone()
        return dict(row) if row else None

    def record_extract(
        self, *, trace_id: str | None, requester: str, found: bool, confidence: float, ber: float
    ) -> str:
        conn = self._conn()
        eid = "ex_" + uuid.uuid4().hex[:12]
        conn.execute(
            "INSERT INTO extracts (id, trace_id, requester, found, confidence, ber, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (eid, trace_id, requester, 1 if found else 0, float(confidence), float(ber), _utcnow()),
        )
        conn.commit()
        return eid

    def count_month(self, tenant_id: str) -> int:
        month = datetime.now(timezone.utc).strftime("%Y-%m")
        row = self._conn().execute(
            "SELECT COUNT(*) AS c FROM traces WHERE tenant_id = ? AND created_at LIKE ?",
            (tenant_id, f"{month}%"),
        ).fetchone()
        return int(row["c"])

    # ------------------------------------------------------------ 审计哈希链

    def append_audit(self, action: str, actor: str | None, target: str | None) -> dict:
        conn = self._conn()
        row = conn.execute("SELECT this_hash FROM audit_logs ORDER BY id DESC LIMIT 1").fetchone()
        prev = row["this_hash"] if row else "0" * 64
        at = _utcnow()
        entry = {"action": action, "actor": actor, "target": target, "at": at, "prev": prev}
        this = _sha256((prev + _canonical(entry)).encode("utf-8"))
        conn.execute(
            "INSERT INTO audit_logs (action, actor, target, prev_hash, this_hash, at)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (action, actor, target, prev, this, at),
        )
        conn.commit()
        return {"action": action, "actor": actor, "target": target, "at": at,
                "prev_hash": prev, "this_hash": this}

    def audit_tail(self, limit: int = 20) -> list[dict]:
        rows = self._conn().execute(
            "SELECT * FROM audit_logs ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [dict(r) for r in reversed(rows)]

    def verify_chain(self) -> tuple[bool, int | None]:
        """校验整条审计链；返回 (是否完整, 首个坏记录 id)。"""
        rows = self._conn().execute("SELECT * FROM audit_logs ORDER BY id ASC").fetchall()
        prev = "0" * 64
        for row in rows:
            entry = {
                "action": row["action"],
                "actor": row["actor"],
                "target": row["target"],
                "at": row["at"],
                "prev": prev,
            }
            expected = _sha256((prev + _canonical(entry)).encode("utf-8"))
            if row["prev_hash"] != prev or row["this_hash"] != expected:
                return False, int(row["id"])
            prev = row["this_hash"]
        return True, None

    def export_rows(self, table: str, limit: int = 10000) -> Iterable[dict]:
        if table not in {"tenants", "users", "assets", "traces", "extracts", "audit_logs"}:
            raise StoreError(f"unknown table {table!r}")
        rows = self._conn().execute(f"SELECT * FROM {table} LIMIT ?", (limit,)).fetchall()
        return [dict(r) for r in rows]
