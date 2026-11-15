# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""证据包：把「原图哈希 + 成图哈希 + 嵌入记录 + 审计链 + 校验脚本」打成一个 ZIP。

设计目标：**离开本系统也能验**。包内 ``verify.py`` 只用标准库，任何人拿到 ZIP 后
``python verify.py`` 即可核对哈希与哈希链，不必信任我们的服务。
"""

from __future__ import annotations

import hashlib
import io
import json
import zipfile
from datetime import datetime, timezone

from .store import Store

IMMUTABLE_NAME = "manifest.json"

VERIFY_SCRIPT = '''#!/usr/bin/env python3
"""证据包独立校验脚本（仅依赖 Python 标准库）。

用法：python verify.py
校验项：
  1. manifest.json 里记录的每个文件哈希与 ZIP 内实际文件一致；
  2. 审计链（chain.jsonl）逐条 prev_hash/this_hash 连续且未被篡改；
  3. 打印追溯码与嵌入时间，便于人工核对。
"""
import hashlib, json, os, sys, zipfile

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def main(here=None):
    here = here or os.path.dirname(os.path.abspath(__file__))
    ok = True
    with open(os.path.join(here, "manifest.json"), "r", encoding="utf-8") as fh:
        manifest = json.load(fh)

    for name, expected in manifest["files"].items():
        path = os.path.join(here, name)
        if not os.path.exists(path):
            print("[MISS] %s" % name); ok = False; continue
        with open(path, "rb") as fh:
            actual = sha256(fh.read())
        if actual != expected:
            print("[FAIL] %s hash mismatch" % name); ok = False
        else:
            print("[ OK ] %s" % name)

    prev = manifest["audit_chain_start"]
    chain_ok = True
    chain_path = os.path.join(here, "chain.jsonl")
    if os.path.exists(chain_path):
        with open(chain_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                entry = json.loads(line)
                payload = json.dumps(
                    {"action": entry["action"], "actor": entry["actor"],
                     "target": entry["target"], "at": entry["at"], "prev": prev},
                    sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                )
                expected = sha256((prev + payload).encode("utf-8"))
                if entry["prev_hash"] != prev or entry["this_hash"] != expected:
                    print("[FAIL] audit chain broken at %s" % entry.get("id")); chain_ok = False; break
                prev = entry["this_hash"]
    print("[%s] audit chain" % (" OK " if chain_ok else "FAIL"))
    ok = ok and chain_ok

    trace = manifest["trace"]
    print("trace_id   :", trace["trace_id"])
    print("resource   :", trace["resource_code"])
    print("user_index :", trace["user_index"])
    print("embedded_at:", trace["embedded_at"])
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
'''


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build_evidence_zip(
    store: Store,
    trace_id: str,
    *,
    original_bytes: bytes | None = None,
    watermarked_bytes: bytes | None = None,
    requester: str = "",
) -> tuple[bytes, dict]:
    """生成证据包，返回 (zip 字节, manifest)。"""
    info = store.get_trace(trace_id)
    if not info:
        raise KeyError(f"trace not found: {trace_id}")
    chain_ok, bad = store.verify_chain()
    chain = store.audit_tail(limit=200)

    files: dict[str, str] = {}
    buf = io.BytesIO()
    manifest = {
        "format": "invismark-evidence/1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator": "invisMark v0.1（零依赖参考实现）",
        "trace": {
            "trace_id": info["trace_id"],
            "resource_code": info["resource_code"],
            "user_index": info["user_index"],
            "user_external_id": info.get("external_id"),
            "embedded_at": info["embedded_at"],
            "seed_version": info["seed_version"],
        },
        "asset": {
            "id": info["asset_id"],
            "sha256_orig": info.get("sha256_orig"),
            "sha256_wm": info.get("sha256_wm"),
            "width": info.get("width"),
            "height": info.get("height"),
            "psnr": info.get("psnr"),
            "ssim": info.get("ssim"),
        },
        "audit_chain_ok": chain_ok,
        "audit_chain_bad_id": bad,
        "audit_chain_start": chain[0]["prev_hash"] if chain else "0" * 64,
        "requester": requester,
        "known_limits": [
            "盲水印只证明「这张图曾由本系统嵌入该追溯码」，不阻断复制；",
            "强压缩/重编码/裁剪会降低检出率，实测矩阵见 docs/ARCHITECTURE.md；",
            "不含第三方 RFC 3161 时间戳，时间可信度依赖本机时钟与审计链。",
        ],
    }
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        def put(name: str, data: bytes) -> None:
            zf.writestr(name, data)
            files[name] = _sha(data)

        if original_bytes is not None:
            put("original.png", original_bytes)
        if watermarked_bytes is not None:
            put("watermarked.png", watermarked_bytes)
        put("chain.jsonl", "".join(json.dumps(e, ensure_ascii=False) + "\n" for e in chain).encode("utf-8"))
        put("verify.py", VERIFY_SCRIPT.encode("utf-8"))
        manifest["files"] = dict(files)
        zf.writestr(IMMUTABLE_NAME, json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8"))
    return buf.getvalue(), manifest
