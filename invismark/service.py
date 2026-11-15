# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""业务服务层：把「算法内核 + 追溯映射 + 证据包」拼成可被 CLI / HTTP / 桌面端复用的 API。

所有方法都返回可直接 json 序列化的 dict；二进制（成图、证据包）单独返回。
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any

from . import evidence
from .config import Settings
from .core import image as imageio
from .core import pipeline, trace
from .store import Store, StoreError


class ServiceError(RuntimeError):
    """业务错误，``code`` 对应 HTTP 状态码/CLI 退出码。"""

    def __init__(self, message: str, code: str = "bad_request", status: int = 400):
        super().__init__(message)
        self.code = code
        self.status = status


@dataclass
class EmbedOutcome:
    payload: dict[str, Any]
    image: bytes            # PNG/JPEG 成图字节
    filename: str


class Service:
    def __init__(self, settings: Settings | None = None, store: Store | None = None):
        self.settings = settings or Settings()
        self.store = store or Store(self.settings.db_path)
        self.tenant_id = self.store.ensure_tenant(self.settings.default_tenant)

    # ------------------------------------------------------------ 配额

    def quota(self, tenant: str | None = None) -> dict:
        tid = self._tenant(tenant)
        used = self.store.count_month(tid)
        limit = self.settings.quota_monthly
        return {
            "tenant_id": tid,
            "month": __import__("datetime").datetime.now().strftime("%Y-%m"),
            "used": used,
            "limit": limit,
            "remaining": max(0, limit - used),
        }

    def _tenant(self, name: str | None) -> str:
        if not name or name == self.settings.default_tenant:
            return self.tenant_id
        return self.store.ensure_tenant(name)

    def _check_quota(self, tenant_id: str) -> None:
        q = self.quota(tenant_id)
        if q["used"] >= q["limit"]:
            raise ServiceError("monthly quota exceeded", code="quota_exceeded", status=429)

    # ------------------------------------------------------------ 嵌入

    def embed(
        self,
        image_bytes: bytes,
        *,
        tenant: str | None = None,
        user: str = "anonymous",
        resource_code: str = "",
        alpha: float | None = None,
        base_long_edge: int | None = None,
        keep_original: bytes | None = None,
    ) -> EmbedOutcome:
        tid = self._tenant(tenant)
        self._check_quota(tid)
        rgb = self._decode(image_bytes)
        h, w = rgb.shape[:2]
        if max(h, w) < pipeline.MIN_LONG_EDGE:
            raise ServiceError(
                f"image too small: long edge {max(h, w)}px < {pipeline.MIN_LONG_EDGE}px",
                code="too_small",
                status=422,
            )
        uid, user_index = self.store.ensure_user(tid, user)
        code = trace.TraceCode.new(
            resource_code=resource_code or self._auto_resource_code(),
            user_index=user_index,
        )
        try:
            res = pipeline.embed(
                rgb,
                code,
                self.settings.seed_for(tid),
                alpha=alpha or self.settings.alpha,
                base_long_edge=base_long_edge or self.settings.base_long_edge,
            )
        except pipeline.InvisMarkError as exc:
            raise ServiceError(str(exc), code="embed_failed", status=422) from exc

        out_bytes = imageio.save_bytes(res.image, "png")
        sha_orig = hashlib.sha256(image_bytes).hexdigest()
        asset_id = self.store.record_embed(
            code,
            tenant_id=tid,
            user_id=uid,
            sha256_orig=sha_orig,
            sha256_wm=hashlib.sha256(out_bytes).hexdigest(),
            uri_wm="",
            width=w,
            height=h,
            psnr=res.psnr,
            ssim=res.ssim,
        )
        payload = {
            "asset_id": asset_id,
            "trace_id": code.hex,
            "resource_code": code.resource_code,
            "user_index": user_index,
            "image_url": f"/v1/assets/{asset_id}",
            "quality": {
                "psnr": None if res.psnr == float("inf") else round(res.psnr, 2),
                "ssim": round(res.ssim, 4),
                "base_size": list(res.base_size),
                "blocks_per_bit": res.blocks_per_bit,
            },
            "embedded_at": code.embedded_at.isoformat(),
            "elapsed_ms": round(res.elapsed_ms, 1),
        }
        return EmbedOutcome(payload=payload, image=out_bytes, filename=f"{code.hex}.png")

    def _auto_resource_code(self) -> str:
        return "F" + format(abs(int.from_bytes(__import__("os").urandom(2), "big")), "05X")[:5]

    # ------------------------------------------------------------ 提取

    def extract(self, image_bytes: bytes, *, requester: str = "anonymous",
                base_long_edge: int | None = None) -> dict:
        rgb = self._decode(image_bytes)
        res = pipeline.extract(
            rgb, self.settings.seed_for(self.tenant_id),
            base_long_edge=base_long_edge or self.settings.base_long_edge,
        )
        self.store.record_extract(
            trace_id=res.trace_id, requester=requester, found=res.found,
            confidence=res.confidence, ber=res.ber,
        )
        if not res.found:
            return {"found": False, "reason": res.reason, "confidence": 0.0,
                    "elapsed_ms": round(res.elapsed_ms, 1)}
        info = self.store.get_trace(res.trace_id or "")
        return {
            "found": True,
            "trace_id": res.trace_id,
            "resource_code": res.trace.resource_code if res.trace else None,
            "user_index": res.trace.user_index if res.trace else None,
            "user": {"external_id": info.get("external_id")} if info else None,
            "embedded_at": res.trace.embedded_at.isoformat() if res.trace else None,
            "confidence": round(res.confidence, 4),
            "corrected_bytes": res.corrected_bytes,
            "ber": round(res.ber, 4),
            "registered": bool(info),
            "report_hint": f"invisMark evidence {res.trace_id}",
            "elapsed_ms": round(res.elapsed_ms, 1),
        }

    def trace_info(self, trace_id: str) -> dict:
        info = self.store.get_trace(trace_id)
        if not info:
            raise ServiceError("trace not found", code="not_found", status=404)
        return {
            "trace_id": info["trace_id"],
            "tenant_id": info["tenant_id"],
            "asset_id": info["asset_id"],
            "resource_code": info["resource_code"],
            "user_index": info["user_index"],
            "user": {"external_id": info.get("external_id")},
            "embedded_at": info["embedded_at"],
            "sha256_orig": info.get("sha256_orig"),
            "sha256_wm": info.get("sha256_wm"),
            "size": {"width": info.get("width"), "height": info.get("height")},
            "quality": {"psnr": info.get("psnr"), "ssim": info.get("ssim")},
        }

    def evidence_zip(self, trace_id: str, *, original_bytes: bytes | None = None,
                     watermarked_bytes: bytes | None = None, requester: str = "") -> bytes:
        try:
            data, _manifest = evidence.build_evidence_zip(
                self.store, trace_id,
                original_bytes=original_bytes,
                watermarked_bytes=watermarked_bytes,
                requester=requester,
            )
        except KeyError as exc:
            raise ServiceError(str(exc), code="not_found", status=404) from exc
        return data

    # ------------------------------------------------------------ 离线号段

    def reserve(self, count: int, *, tenant: str | None = None, user: str = "offline") -> list[str]:
        """为桌面端离线模式预分配 trace_id（只登记映射，不落图）。"""
        if not (1 <= count <= 1000):
            raise ServiceError("count must be 1..1000", code="bad_request")
        tid = self._tenant(tenant)
        _uid, user_index = self.store.ensure_user(tid, user)
        codes = []
        for i in range(count):
            code = trace.TraceCode.new(
                resource_code=self._auto_resource_code(), user_index=user_index, serial=i
            )
            self.store.record_embed(
                code, tenant_id=tid, user_id=_uid,
                sha256_orig="", sha256_wm="", uri_wm="",
                width=0, height=0, psnr=0.0, ssim=0.0,
            )
            codes.append(code.hex)
        return codes

    def verify_chain(self) -> dict:
        ok, bad = self.store.verify_chain()
        return {"ok": ok, "bad_id": bad, "tail": self.store.audit_tail(5)}

    # ------------------------------------------------------------ 工具

    @staticmethod
    def _decode(image_bytes: bytes):
        try:
            return imageio.load_bytes(image_bytes)
        except imageio.ImageIOError as exc:
            raise ServiceError(str(exc), code="undecodable", status=400) from exc
