# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""GF(2^8) 有限域运算：本原多项式 0x11D，生成元 α=2。

零第三方依赖，纯 Python 查表实现；表在模块导入时构建一次（各 512 字节）。
"""

from __future__ import annotations

PRIMITIVE_POLY = 0x11D  # x^8 + x^4 + x^3 + x^2 + 1
GENERATOR = 2

EXP: list[int] = [0] * 512
LOG: list[int] = [0] * 256


def _build_tables() -> None:
    x = 1
    for i in range(255):
        EXP[i] = x
        LOG[x] = i
        x <<= 1
        if x & 0x100:
            x ^= PRIMITIVE_POLY
    # 扩展成 512 长度，省去乘方时的取模
    for i in range(255, 512):
        EXP[i] = EXP[i - 255]
    LOG[0] = 0  # 未定义，调用方需避免


_build_tables()


def gf_mul(a: int, b: int) -> int:
    """域内乘法。"""
    if a == 0 or b == 0:
        return 0
    return EXP[LOG[a] + LOG[b]]


def gf_div(a: int, b: int) -> int:
    """域内除法（b != 0）。"""
    if b == 0:
        raise ZeroDivisionError("GF(256) division by zero")
    if a == 0:
        return 0
    return EXP[(LOG[a] - LOG[b]) % 255]


def gf_pow(base: int, exp: int) -> int:
    """域内乘方，exp 可为负（自动对 255 取模）。"""
    if exp == 0:
        return 1
    if base == 0:
        return 0
    return EXP[(LOG[base] * exp) % 255]


def gf_inverse(a: int) -> int:
    if a == 0:
        raise ZeroDivisionError("GF(256) inverse of zero")
    return EXP[255 - LOG[a]]


def poly_eval(poly: list[int], x: int) -> int:
    """多项式求值（Horner），poly[0] 为最高次项系数。"""
    y = 0
    for coef in poly:
        y = gf_mul(y, x) ^ coef
    return y


def poly_mul(p: list[int], q: list[int]) -> list[int]:
    """多项式乘法（系数在 GF(256)）。"""
    out = [0] * (len(p) + len(q) - 1)
    for i, a in enumerate(p):
        if a == 0:
            continue
        for j, b in enumerate(q):
            out[i + j] ^= gf_mul(a, b)
    return out


def poly_add(p: list[int], q: list[int]) -> list[int]:
    """多项式加法（长度对齐，缺项补零）。"""
    n = max(len(p), len(q))
    out = [0] * n
    for i, v in enumerate(p):
        out[n - len(p) + i] = v
    for i, v in enumerate(q):
        out[n - len(q) + i] ^= v
    return out
