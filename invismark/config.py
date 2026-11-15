# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""运行配置，全部可用环境变量覆盖（12-Factor）。"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from .core import pipeline


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


@dataclass
class Settings:
    """一个进程一套配置；私有化部署时改这一个结构体/环境变量即可。"""

    db_path: str = field(default_factory=lambda: os.environ.get("INVISMARK_DB", "invismark.db"))
    data_dir: str = field(default_factory=lambda: os.environ.get("INVISMARK_DATA", "data"))
    seed: int = field(default_factory=lambda: _env_int("INVISMARK_SEED", 20260115))
    alpha: float = field(default_factory=lambda: _env_float("INVISMARK_ALPHA", pipeline.DEFAULT_ALPHA))
    base_long_edge: int = field(
        default_factory=lambda: _env_int("INVISMARK_BASE_LONG_EDGE", pipeline.BASE_LONG_EDGE)
    )
    default_tenant: str = field(
        default_factory=lambda: os.environ.get("INVISMARK_TENANT", "default")
    )
    quota_monthly: int = field(default_factory=lambda: _env_int("INVISMARK_QUOTA", 10000))
    host: str = field(default_factory=lambda: os.environ.get("INVISMARK_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: _env_int("INVISMARK_PORT", 8000))

    def data_path(self, name: str = "") -> Path:
        p = Path(self.data_dir)
        p.mkdir(parents=True, exist_ok=True)
        return p / name if name else p

    def seed_for(self, tenant: str) -> int:
        """租户级 seed：同一主 seed 下按租户名派生，便于密钥轮换（seed_version）。"""
        import hashlib

        digest = hashlib.sha256(f"{self.seed}:{tenant}".encode("utf-8")).digest()
        return int.from_bytes(digest[:8], "big")
