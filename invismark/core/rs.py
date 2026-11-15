# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""Reed–Solomon RS(64,24) over GF(256)。

- 码字 64 字节 = 24 字节载荷 + 40 字节校验，可纠正 20 字节随机错误（约 31% 误码容忍）；
- 由 RS(255,215) 缩短 191 个信息位得到（校验位 40 不变），前导 0 不影响校验位计算；
- 解码使用 Berlekamp–Massey + Chien 搜索 + Forney 求值，纯 Python 实现。

对外接口：
    encode(payload: bytes) -> bytes            # 24 B -> 64 B
    decode(codeword: bytes) -> DecodeResult    # 64 B -> 24 B（失败时返回 ok=False，不抛异常）
"""

from __future__ import annotations

from dataclasses import dataclass

from . import gf256 as gf

NSYM = 40          # 校验位数量
K = 24             # 载荷字节数
N = K + NSYM       # 码字长度 64
FULL_N = 255       # 完整码长（缩短前）
FCR = 0            # 首个连续根 α^0
GENERATOR = 2


def _poly_scale(p: list[int], x: int) -> list[int]:
    if x == 0:
        return [0] * len(p)
    return [gf.gf_mul(c, x) for c in p]


def _poly_eval(p: list[int], x: int) -> int:
    return gf.poly_eval(p, x)


def _poly_add(p: list[int], q: list[int]) -> list[int]:
    return gf.poly_add(p, q)


def _poly_div(dividend: list[int], divisor: list[int]) -> tuple[list[int], list[int]]:
    """多项式带余除法，返回 (商, 余数)，系数均为 GF(256)。除式首项须非零。"""
    out = list(dividend)
    msg_out = [0] * (len(dividend) - len(divisor) + 1)
    for i in range(len(msg_out)):
        coef = out[i]
        if coef != 0:
            for j in range(1, len(divisor)):
                if divisor[j] != 0:
                    out[i + j] ^= gf.gf_mul(divisor[j], coef)
        msg_out[i] = coef
    return msg_out, out[len(msg_out):]


def generator_poly() -> list[int]:
    """RS 生成多项式，根为 α^0 … α^(NSYM-1)，最高次项系数为 1。"""
    g = [1]
    for i in range(NSYM):
        g = gf.poly_mul(g, [1, gf.gf_pow(GENERATOR, i + FCR)])
    return g


_GEN = generator_poly()


def encode(payload: bytes) -> bytes:
    """24 字节载荷 -> 64 字节系统码字。

    对 M(x)·x^40 做多项式长除，余数即 40 字节校验位；商被丢弃，故消息部分原样保留。
    """
    if len(payload) != K:
        raise ValueError(f"payload must be exactly {K} bytes, got {len(payload)}")
    msg = list(payload) + [0] * NSYM
    for i in range(K):
        coef = msg[i]
        if coef != 0:
            for j in range(len(_GEN)):  # j=0 即把当前项除尽
                msg[i + j] ^= gf.gf_mul(_GEN[j], coef)
    return bytes(payload) + bytes(msg[K:])


@dataclass(frozen=True)
class DecodeResult:
    ok: bool
    payload: bytes | None
    corrected: int      # 纠正的字节数（估计）
    ber: float          # 纠正字节数 / 码字长度
    message: str = ""


def _calc_syndromes(msg: list[int]) -> list[int]:
    # 首位 0 用于索引对齐（与 Berlekamp–Massey 的 K 偏移约定一致）
    return [0] + [_poly_eval(msg, gf.gf_pow(GENERATOR, i + FCR)) for i in range(NSYM)]


def _find_error_locator(synd: list[int]) -> list[int]:
    err_loc = [1]
    old_loc = [1]
    for i in range(NSYM):
        # synd 首位为占位 0，故按 reedsolo 的 synd_shift 约定 +1 取用
        k = i + 1
        delta = synd[k]
        for j in range(1, len(err_loc)):
            delta ^= gf.gf_mul(err_loc[-(j + 1)], synd[k - j])
        old_loc = old_loc + [0]
        if delta != 0:
            if len(old_loc) > len(err_loc):
                new_loc = _poly_scale(old_loc, delta)
                old_loc = _poly_scale(err_loc, gf.gf_inverse(delta))
                err_loc = new_loc
            err_loc = _poly_add(err_loc, _poly_scale(old_loc, delta))
    while len(err_loc) and err_loc[0] == 0:
        del err_loc[0]
    return err_loc


def _find_error_positions(err_loc: list[int], nmess: int) -> list[int]:
    """Chien 搜索。err_loc 为定位多项式（首项为 x^e 系数），返回错误位置（码字下标）。"""
    errs = len(err_loc) - 1
    positions: list[int] = []
    for i in range(nmess):
        if _poly_eval(err_loc, gf.gf_pow(GENERATOR, i)) == 0:
            positions.append(nmess - 1 - i)
    if len(positions) != errs:
        raise ValueError(f"error locator mismatch: found {len(positions)} of {errs}")
    return positions


def _find_errata_locator(coef_pos: list[int]) -> list[int]:
    e_loc = [1]
    for pos in coef_pos:
        e_loc = gf.poly_mul(e_loc, gf.poly_add([1], [gf.gf_pow(GENERATOR, pos), 0]))
    return e_loc


def _find_error_evaluator(synd: list[int], err_loc: list[int], nsym: int) -> list[int]:
    product = gf.poly_mul(synd, err_loc)
    _, remainder = _poly_div(product, [1] + [0] * (nsym + 1))
    return remainder


def _correct_errata(msg: list[int], synd: list[int], err_pos: list[int]) -> list[int]:
    coef_pos = [len(msg) - 1 - p for p in err_pos]
    err_loc = _find_errata_locator(coef_pos)
    err_eval = _find_error_evaluator(synd[::-1], err_loc, len(err_loc) - 1)[::-1]
    # X_i = α^(coef_pos)，与 α^-(255-coef_pos) 同余
    x_arr = [gf.gf_pow(GENERATOR, p) for p in coef_pos]
    e = [0] * len(msg)
    for i, xi in enumerate(x_arr):
        xi_inv = gf.gf_inverse(xi)
        denom = 1
        for j, xj in enumerate(x_arr):
            if i != j:
                denom = gf.gf_mul(denom, (1 ^ gf.gf_mul(xi_inv, xj)))
        y = _poly_eval(err_eval[::-1], xi_inv)
        y = gf.gf_mul(gf.gf_pow(xi, 1 - FCR), y)
        magnitude = gf.gf_div(y, denom)
        e[err_pos[i]] = magnitude
    return _poly_add(msg, e)


def decode(codeword: bytes) -> DecodeResult:
    """64 字节码字 -> 24 字节载荷。失败不抛异常，返回 ok=False。"""
    if len(codeword) != N:
        return DecodeResult(False, None, 0, 1.0, f"codeword must be {N} bytes, got {len(codeword)}")
    # 缩短码：补齐前导 191 个 0，按完整 255 码字解码
    full = [0] * (FULL_N - N) + list(codeword)
    synd = _calc_syndromes(full)
    if max(synd) == 0:
        return DecodeResult(True, codeword[:K], 0, 0.0)
    try:
        err_loc = _find_error_locator(synd)
        errs = len(err_loc) - 1
        if errs == 0:
            return DecodeResult(False, None, 0, 1.0, "locator degree 0")
        if errs > NSYM // 2:
            return DecodeResult(False, None, 0, 1.0, f"too many errors: {errs}")
        # 与 reedsolo 一致：Chien 搜索使用倒序定位多项式
        err_pos = _find_error_positions(err_loc[::-1], FULL_N)
        corrected = _correct_errata(full, synd, err_pos)
        # 校验修正结果
        if max(_calc_syndromes(corrected)) != 0:
            return DecodeResult(False, None, 0, 1.0, "syndrome check failed after correction")
        fixed = bytes(corrected[FULL_N - N:])
        n_err = len(err_pos)
        return DecodeResult(True, fixed[:K], n_err, n_err / N)
    except (ValueError, ZeroDivisionError) as exc:  # 错误数超限等
        return DecodeResult(False, None, 0, 1.0, str(exc))
