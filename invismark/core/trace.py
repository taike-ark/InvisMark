# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""24 字节追溯码（trace_id）的编码与解析。

字节布局（共 24 B，网络序）::

    0        version          u8      格式版本，当前为 1
    1..4     resource_code    u32     base36 资源编码（最多 6 位，字母大写）
    5..6     user_index       u16     用户索引（与真实用户 ID 在服务端映射，水印内不含明文 PII）
    7..10    embedded_minute  u32     嵌入时刻（UTC 分钟，自 2020-01-01 起）
    11..14   serial           u32     序号（离线预分配号段用）
    15..18   crc32            u32     前 15 字节的 CRC32
    19..23   reserved         5 B     保留位，必须为 0

CRC32 与保留位构成「双门限」的第二道校验：RS 解码成功且 CRC 通过才判定命中，
可把误报压到极低（详见 docs/ARCHITECTURE.md）。
"""

from __future__ import annotations

import zlib
from dataclasses import dataclass
from datetime import datetime, timezone

VERSION = 1
EPOCH = datetime(2020, 1, 1, tzinfo=timezone.utc)
ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CODE_LEN = 6
MAX_USER_INDEX = 0xFFFF
MAX_SERIAL = 0xFFFFFFFF
MAX_MINUTE = 0xFFFFFFFF
PAYLOAD_LEN = 15  # 参与 CRC 的字节数
TRACE_LEN = 24


class TraceFormatError(ValueError):
    """追溯码格式非法（版本/CRC/保留位/字段越界）。"""


def _encode_code(code: str) -> int:
    code = code.strip().upper()
    if not code or len(code) > CODE_LEN:
        raise TraceFormatError(f"resource_code must be 1..{CODE_LEN} chars, got {code!r}")
    value = 0
    for ch in code.rjust(CODE_LEN, "0"):
        idx = ALPHABET.find(ch)
        if idx < 0:
            raise TraceFormatError(f"invalid base36 char {ch!r} in resource_code")
        value = value * 36 + idx
    return value


def _decode_code(value: int) -> str:
    chars = []
    v = value
    for _ in range(CODE_LEN):
        chars.append(ALPHABET[v % 36])
        v //= 36
    return "".join(reversed(chars))


def _minute_of(dt: datetime) -> int:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    delta = dt.astimezone(timezone.utc) - EPOCH
    return int(delta.total_seconds()) // 60


def _datetime_of(minute: int) -> datetime:
    from datetime import timedelta

    return EPOCH + timedelta(minutes=int(minute))


@dataclass(frozen=True)
class TraceCode:
    """一条 24 字节追溯码。"""

    resource_code: str
    user_index: int
    embedded_at: datetime
    serial: int = 0
    version: int = VERSION

    # ---- 构造 ----
    @classmethod
    def new(
        cls,
        resource_code: str,
        user_index: int,
        embedded_at: datetime | None = None,
        serial: int = 0,
    ) -> "TraceCode":
        if not (0 <= int(user_index) <= MAX_USER_INDEX):
            raise TraceFormatError(f"user_index out of range: {user_index}")
        if not (0 <= int(serial) <= MAX_SERIAL):
            raise TraceFormatError(f"serial out of range: {serial}")
        code = resource_code.strip().upper()
        _encode_code(code)  # 提前校验
        return cls(
            resource_code=code.rjust(CODE_LEN, "0"),
            user_index=int(user_index),
            embedded_at=(embedded_at or datetime.now(timezone.utc)).astimezone(timezone.utc),
            serial=int(serial),
        )

    # ---- 序列化 ----
    def to_bytes(self) -> bytes:
        minute = _minute_of(self.embedded_at)
        if minute < 0 or minute > MAX_MINUTE:
            raise TraceFormatError(f"embedded_at out of representable range: {self.embedded_at}")
        head = bytearray()
        head.append(self.version & 0xFF)
        head += _encode_code(self.resource_code).to_bytes(4, "big")
        head += int(self.user_index).to_bytes(2, "big")
        head += minute.to_bytes(4, "big")
        head += int(self.serial).to_bytes(4, "big")
        crc = zlib.crc32(bytes(head)) & 0xFFFFFFFF
        return bytes(head) + crc.to_bytes(4, "big") + b"\x00" * 5

    @classmethod
    def from_bytes(cls, data: bytes) -> "TraceCode":
        if len(data) != TRACE_LEN:
            raise TraceFormatError(f"trace_id must be {TRACE_LEN} bytes, got {len(data)}")
        data = bytes(data)
        if data[0] != VERSION:
            raise TraceFormatError(f"unsupported version byte: {data[0]}")
        crc = int.from_bytes(data[15:19], "big")
        if zlib.crc32(data[:PAYLOAD_LEN]) & 0xFFFFFFFF != crc:
            raise TraceFormatError("crc32 mismatch")
        if any(data[19:24]):
            raise TraceFormatError("reserved bytes must be zero")
        resource = _decode_code(int.from_bytes(data[1:5], "big"))
        user_index = int.from_bytes(data[5:7], "big")
        minute = int.from_bytes(data[7:11], "big")
        serial = int.from_bytes(data[11:15], "big")
        return cls(
            resource_code=resource,
            user_index=user_index,
            embedded_at=_datetime_of(minute),
            serial=serial,
            version=data[0],
        )

    # ---- 便捷形式 ----
    @property
    def hex(self) -> str:
        """48 位十六进制串（对外展示/日志用）。"""
        return self.to_bytes().hex().upper()

    @classmethod
    def from_hex(cls, text: str) -> "TraceCode":
        text = text.strip().replace("-", "").replace(" ", "")
        try:
            raw = bytes.fromhex(text)
        except ValueError as exc:
            raise TraceFormatError(f"bad hex trace_id: {text!r}") from exc
        return cls.from_bytes(raw)

    def to_dict(self) -> dict:
        return {
            "trace_id": self.hex,
            "resource_code": self.resource_code,
            "user_index": self.user_index,
            "embedded_at": self.embedded_at.isoformat().replace("+00:00", "Z"),
            "serial": self.serial,
            "version": self.version,
        }

    def __str__(self) -> str:  # pragma: no cover - 展示用
        return self.hex
