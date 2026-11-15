# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""盲水印嵌入 / 提取管线（两级 DWT + 分块 DCT + 归一化 AC 系数扩频 + RS 纠错）。

嵌入链路::

    原图 ──► 亮度 Y ──► 缩放到基准长边（默认 2400，需 16 的整数倍）
         ──► 两级 Haar DWT（1/4 分辨率 LL2，等效 16 像素块）
         ──► 4×4 分块 DCT ──► 取中频系数 C(1,1)，用块内 AC 能量归一化
         ──► 每个比特用 K 个块做 ±α 扩频（K 由分辨率决定，24 B 码字共 512 bit）
         ──► 逆变换、差异回注原分辨率

提取链路::

    可疑图 ──► 缩放到同一基准 ──► 同样的 DWT/DCT ──► 归一化系数
           ──► 与种子生成的 ±1 图案做相关，逐比特判决 ──► RS(64,24) 纠错
           ──► CRC32 + 保留位校验 ──► 追溯码（任一步失败 fail-open）

为什么用「归一化 AC 系数 + 扩频」而不是直接量化像素/DCT 绝对值：
- 归一化把整体缩放、亮度/对比度变化约掉（分子分母同比缩放）；
- 扩频把同一比特铺在 K 个块上，单个块的纹理干扰被平均掉；
- 两级 DWT 让比特落在 16 像素尺度，扛得住平台二次压缩（先缩到 1280 长边）。
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Iterable

import numpy as np

from . import image as imageio
from . import rs, trace

BASE_LONG_EDGE = 2400
MIN_LONG_EDGE = 800
BLOCK = 4
BITS_PER_CODEWORD = rs.N * 8  # 512
DEFAULT_ALPHA = 0.60          # 归一化 AC 系数的扩频幅度（0.3 偏保守，0.6 兼顾鲁棒与画质）
MIN_AC_ENERGY = 9.0           # AC 能量下限：纯色/平坦块不参与「内容偏置」估计
MIN_AMPLITUDE = 3.0           # 注入幅度下限（DCT 系数单位），保证平滑图也能扛 8 bit 量化
MAX_AMPLITUDE = 24.0          # 注入幅度上限，避免白/黑区域被截断导致符号翻转


class InvisMarkError(RuntimeError):
    """管线级错误（图片过小、载荷非法等）。"""


# ------------------------------------------------------------------ 变换


def _dct_matrix(n: int = BLOCK) -> np.ndarray:
    m = np.zeros((n, n), dtype=np.float64)
    for k in range(n):
        ck = math.sqrt(1.0 / n) if k == 0 else math.sqrt(2.0 / n)
        for x in range(n):
            m[k, x] = ck * math.cos(math.pi * (2 * x + 1) * k / (2.0 * n))
    return m


_D = _dct_matrix()


def _haar_dwt(y: np.ndarray):
    a = y[0::2, 0::2]
    b = y[0::2, 1::2]
    c = y[1::2, 0::2]
    d = y[1::2, 1::2]
    ll = (a + b + c + d) * 0.5
    hl = (a - b + c - d) * 0.5
    lh = (a + b - c - d) * 0.5
    hh = (a - b - c + d) * 0.5
    return ll, hl, lh, hh


def _haar_idwt(ll, hl, lh, hh) -> np.ndarray:
    a = (ll + hl + lh + hh) * 0.5
    b = (ll - hl + lh - hh) * 0.5
    c = (ll + hl - lh - hh) * 0.5
    d = (ll - hl - lh + hh) * 0.5
    h2, w2 = ll.shape
    out = np.empty((h2 * 2, w2 * 2), dtype=np.float64)
    out[0::2, 0::2] = a
    out[0::2, 1::2] = b
    out[1::2, 0::2] = c
    out[1::2, 1::2] = d
    return out


def _analyze(y: np.ndarray, level: int) -> list:
    """多级 Haar 分解，返回各级四子带（bands[-1][0] 为最粗的 LL）。"""
    bands = []
    cur = y
    for _ in range(level):
        band = _haar_dwt(cur)
        bands.append(band)
        cur = band[0]
    return bands


def _synthesize(bands: list, ll_wm: np.ndarray) -> np.ndarray:
    """用改过的 LL 逐级重建。"""
    cur = ll_wm
    for band in reversed(bands):
        cur = _haar_idwt(cur, band[1], band[2], band[3])
    return cur


def _to_blocks(plane: np.ndarray) -> np.ndarray:
    h, w = plane.shape
    bh, bw = h // BLOCK, w // BLOCK
    blocks = plane[: bh * BLOCK, : bw * BLOCK].reshape(bh, BLOCK, bw, BLOCK)
    return blocks.transpose(0, 2, 1, 3).reshape(bh * bw, BLOCK, BLOCK)


def _from_blocks(blocks: np.ndarray, bh: int, bw: int) -> np.ndarray:
    grid = blocks.reshape(bh, bw, BLOCK, BLOCK).transpose(0, 2, 1, 3)
    return grid.reshape(bh * BLOCK, bw * BLOCK)


def _dct_blocks(blocks: np.ndarray) -> np.ndarray:
    return np.einsum("ij,njk,lk->nil", _D, blocks, _D)


def _idct_blocks(coef: np.ndarray) -> np.ndarray:
    return np.einsum("ji,njl,lk->nik", _D, coef, _D)


def _carrier(coef: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """返回 (归一化中频系数, 块内 AC 能量)。"""
    ac = coef[:, 1:, 1:]
    energy = np.sum(ac * ac, axis=(1, 2))
    c = coef[:, 1, 1] / np.sqrt(np.maximum(energy, 1e-9))
    return c, energy


# ------------------------------------------------------------------ 位序


def _bytes_to_bits(data: bytes) -> np.ndarray:
    return np.unpackbits(np.frombuffer(data, dtype=np.uint8))


def _bits_to_bytes(bits: np.ndarray) -> bytes:
    bits = np.asarray(bits, dtype=np.uint8)[: BITS_PER_CODEWORD]
    if bits.size < BITS_PER_CODEWORD:
        bits = np.concatenate([bits, np.zeros(BITS_PER_CODEWORD - bits.size, np.uint8)])
    return np.packbits(bits).tobytes()


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(int(seed) & 0xFFFFFFFFFFFFFFFF)


def _scramble_order(seed: int) -> np.ndarray:
    return _rng(seed ^ 0x5EED5EED).permutation(BITS_PER_CODEWORD)


def _spread_signs(seed: int, n: int) -> np.ndarray:
    """每个块一个 ±1 扩频符号，返回长度 n（= 512·k）的数组，按 ``块号 % 512`` 归比特。

    关键：**每个比特自己的 k 个块内部正负各半**。自然图的中频系数本身有正偏置
    （c̄≈0.4~0.6），若符号不平衡，相关器会把内容偏置误当水印能量，k 小时直接压过信号。
    组内再用种子洗牌，保证不同租户/图片的图案不同。
    """
    k = n // BITS_PER_CODEWORD
    keep = 2 * (k // 2)                                 # 每比特只用偶数个块，正负严格相等
    ranks = np.arange(k)
    base = np.zeros(k)
    base[: keep // 2] = -1.0
    base[keep // 2:keep] = 1.0                          # 余下的 rank 权重 0（不参与）
    signs = np.tile(base, (BITS_PER_CODEWORD, 1))       # (512, k)
    rng = _rng(seed ^ 0xA11CE)
    for row in signs:
        rng.shuffle(row)
    return signs.T.reshape(-1)                          # 扁平化后 index = b + j*512


# ------------------------------------------------------------------ 结果


@dataclass
class EmbedResult:
    image: np.ndarray
    trace_id: str
    psnr: float
    ssim: float
    alpha: float
    base_size: tuple[int, int]
    blocks_total: int
    blocks_used: int
    blocks_per_bit: int
    elapsed_ms: float
    warnings: list[str] = field(default_factory=list)


@dataclass
class ExtractResult:
    found: bool
    trace: trace.TraceCode | None = None
    confidence: float = 0.0
    corrected_bytes: int = 0
    ber: float = 1.0
    blocks_used: int = 0
    reason: str = ""
    elapsed_ms: float = 0.0

    @property
    def trace_id(self) -> str | None:
        return self.trace.hex if self.trace else None


# ------------------------------------------------------------------ 嵌入


def embed(
    rgb: np.ndarray,
    code: trace.TraceCode,
    seed: int,
    *,
    alpha: float = DEFAULT_ALPHA,
    base_long_edge: int = BASE_LONG_EDGE,
    min_long_edge: int = MIN_LONG_EDGE,
    level: int = 0,
) -> EmbedResult:
    """在 RGB 图像中嵌入 24 字节追溯码，返回成图与画质指标。

    ``level`` 为 DWT 级数（0 = 自动按分辨率选），级数越大承载块越少但越抗缩放。
    """
    import time

    t0 = time.perf_counter()
    rgb = np.asarray(rgb)
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise InvisMarkError("embed expects an (H, W, 3) RGB image")
    h, w = rgb.shape[:2]
    if min(h, w) < 64:
        raise InvisMarkError(f"image too small: {w}x{h}")
    if max(h, w) < min_long_edge:
        raise InvisMarkError(
            f"image long edge {max(h, w)}px is below the {min_long_edge}px minimum for reliable embedding"
        )
    if not (0 < alpha < 1):
        raise InvisMarkError("alpha must be in (0, 1)")

    plane = imageio.to_ycbcr(rgb)
    y_orig, cb, cr = plane

    base_h, base_w = _base_dims(h, w, base_long_edge, level)
    y_base = np.clip(imageio.resize(y_orig, base_h, base_w).astype(np.float64), 0, 255)

    lvl = _auto_level(base_h, base_w, level)
    bands = _analyze(y_base, lvl)
    ll = bands[-1][0]
    blocks = _to_blocks(ll)
    n_blocks = blocks.shape[0]
    k = n_blocks // BITS_PER_CODEWORD
    if k < 1:
        raise InvisMarkError(
            f"base resolution too small: {n_blocks} blocks < {BITS_PER_CODEWORD} bits"
        )
    n_used = BITS_PER_CODEWORD * k

    coef = _dct_blocks(blocks)
    _c, energy = _carrier(coef)

    payload = code.to_bytes()
    codeword = rs.encode(payload)
    raw_bits = _bytes_to_bits(codeword)
    order = _scramble_order(seed)
    bits = raw_bits[order]                       # 置乱后的比特序列
    signs = _spread_signs(seed, n_used)          # 每个块的扩频符号
    bit_of_block = bits[np.arange(n_used) % BITS_PER_CODEWORD]
    wanted = np.where(bit_of_block > 0, 1.0, -1.0) * signs
    # 不做硬掩码：平坦块上 ΔC = α·‖AC‖ ≈ 0，本身无害；解码端按能量加权，
    # 避免「某些比特一个块都没投到票」导致 RS 直接失败。
    # 上限防止高强度块把白/黑区域推过 255/0 被截断（截断会破坏相关符号）
    amp = np.minimum(
        np.maximum(
            alpha * np.sqrt(np.maximum(energy[:n_used], 1e-9)),
            MIN_AMPLITUDE * (2.5 ** (lvl - 1)),
        ),
        MAX_AMPLITUDE * (2.0 ** (lvl - 1)),
    )
    coef[:n_used, 1, 1] += wanted * amp
    ll_wm = _from_blocks(_idct_blocks(coef), ll.shape[0] // BLOCK, ll.shape[1] // BLOCK)
    y_wm_base = _synthesize(bands, ll_wm)

    diff = y_wm_base - y_base
    if (base_h, base_w) != (h, w):
        diff = imageio.resize(diff, h, w).astype(np.float64)
    out = imageio.from_ycbcr(np.clip(y_orig + diff, 0, 255), cb, cr)

    return EmbedResult(
        image=out,
        trace_id=code.hex,
        psnr=imageio.psnr(rgb, out),
        ssim=imageio.ssim(rgb, out),
        alpha=float(alpha),
        base_size=(base_h, base_w),
        blocks_total=int(n_blocks),
        blocks_used=int(np.sum(energy[:n_used] > MIN_AC_ENERGY)),
        blocks_per_bit=int(k),
        elapsed_ms=(time.perf_counter() - t0) * 1000.0,
    )


def _auto_level(base_h: int, base_w: int, level: int) -> int:
    """自动选 DWT 级数：保证每比特至少 ~8 个块（更稳），否则退回低一级。"""
    if level:
        return int(level)
    for lvl in (2, 1):
        blocks = (base_h // (2 ** lvl) // BLOCK) * (base_w // (2 ** lvl) // BLOCK)
        if blocks // BITS_PER_CODEWORD >= 8:
            return lvl
    return 1


# ------------------------------------------------------------------ 提取


def _base_dims(h: int, w: int, base_long_edge: int, level: int) -> tuple[int, int]:
    factor = 2 ** max(1, int(level))
    return imageio.fit_long_edge(h, w, base_long_edge, multiple=8 * factor)


def _demodulate(
    y: np.ndarray, base_long_edge: int, n_bits: int, seed: int, level: int = 0
) -> tuple[np.ndarray, int]:
    """返回 (每比特相关性得分, 参与统计的块数)。"""
    h, w = y.shape
    base_h, base_w = _base_dims(h, w, base_long_edge, level)
    y_base = np.clip(imageio.resize(y, base_h, base_w).astype(np.float64), 0, 255)
    lvl = _auto_level(base_h, base_w, level)
    bands = _analyze(y_base, lvl)
    blocks = _to_blocks(bands[-1][0])
    coef = _dct_blocks(blocks)
    _c, energy = _carrier(coef)
    n = blocks.shape[0]
    k = n // n_bits
    if k < 1:
        return np.zeros(n_bits), 0
    n_used = n_bits * k
    signs = _spread_signs(seed, n_used)
    e = energy[:n_used]
    # 匹配滤波：水印以绝对幅度注入中频系数，直接对绝对系数做相关（增益不变量，缩放/对比度
    # 变化只会等比缩放，不改变相关符号）。
    amp = coef[:n_used, 1, 1].copy()
    ok = e > MIN_AC_ENERGY
    if ok.any():
        amp = amp - float(np.mean(amp[ok]))              # 去掉内容自带的中频偏置
    # 再按比特组去一次偏置：文字/条纹类图像的偏置是空间局部的，全局均值去不干净
    idx = np.arange(n_used) % n_bits
    bit_sum = np.zeros(n_bits)
    bit_cnt = np.zeros(n_bits)
    np.add.at(bit_sum, idx, amp)
    np.add.at(bit_cnt, idx, 1.0)
    amp = amp - (bit_sum / np.maximum(bit_cnt, 1.0))[idx]
    weighted = amp * signs
    score = np.zeros(n_bits)
    np.add.at(score, np.arange(n_used) % n_bits, weighted)
    return score, int(ok.sum())


def _decode_scores(score: np.ndarray, blocks_used: int, seed: int) -> ExtractResult:
    bits = (score > 0).astype(np.uint8)
    order = _scramble_order(seed)
    raw = np.zeros_like(bits)
    raw[order] = bits                                   # 反置乱
    codeword = _bits_to_bytes(raw)
    dec = rs.decode(codeword)
    if not dec.ok or dec.payload is None:
        return ExtractResult(False, reason=dec.message or "rs decode failed", ber=dec.ber,
                             blocks_used=blocks_used)
    try:
        code = trace.TraceCode.from_bytes(dec.payload)
    except trace.TraceFormatError as exc:
        return ExtractResult(False, reason=f"trace check failed: {exc}", ber=dec.ber,
                             blocks_used=blocks_used)
    margin = float(np.min(np.abs(score))) / (float(np.mean(np.abs(score))) or 1.0)
    confidence = float(np.clip(0.5 * (1.0 - dec.corrected / rs.NSYM) + 0.5 * min(margin, 1.0), 0.0, 1.0))
    return ExtractResult(
        found=True,
        trace=code,
        confidence=confidence,
        corrected_bytes=dec.corrected,
        ber=dec.ber,
        blocks_used=blocks_used,
        reason="ok",
    )


def extract(
    rgb: np.ndarray,
    seed: int,
    *,
    alpha: float = DEFAULT_ALPHA,
    base_long_edge: int = BASE_LONG_EDGE,
    level: int = 0,
) -> ExtractResult:
    """从图像中提取追溯码；失败时 fail-open 返回 found=False。"""
    import time

    t0 = time.perf_counter()
    rgb = np.asarray(rgb)
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise InvisMarkError("extract expects an (H, W, 3) RGB image")
    y, _cb, _cr = imageio.to_ycbcr(rgb)
    score, used = _demodulate(y, base_long_edge, BITS_PER_CODEWORD, int(seed), level)
    res = _decode_scores(score, used, seed)
    res.elapsed_ms = (time.perf_counter() - t0) * 1000.0
    return res


# ------------------------------------------------------------------ 文件/批量


def embed_file(
    src: str,
    dst: str,
    code: trace.TraceCode,
    seed: int,
    *,
    alpha: float = DEFAULT_ALPHA,
    base_long_edge: int = BASE_LONG_EDGE,
) -> EmbedResult:
    rgb = imageio.load(src)
    res = embed(rgb, code, seed, alpha=alpha, base_long_edge=base_long_edge)
    imageio.save(dst, res.image)
    return res


def extract_file(
    src: str,
    seed: int,
    *,
    alpha: float = DEFAULT_ALPHA,
    base_long_edge: int = BASE_LONG_EDGE,
) -> ExtractResult:
    return extract(imageio.load(src), seed, alpha=alpha, base_long_edge=base_long_edge)


def embed_batch(
    jobs: Iterable[tuple[str, str]],
    code_factory,
    seed: int,
    *,
    alpha: float = DEFAULT_ALPHA,
    progress=None,
) -> list[tuple[str, str, EmbedResult | Exception]]:
    """批量嵌入；``code_factory(index, src)`` 返回每张图对应的 TraceCode。"""
    results: list[tuple[str, str, EmbedResult | Exception]] = []
    for i, (src, dst) in enumerate(jobs):
        try:
            res = embed_file(src, dst, code_factory(i, src), seed, alpha=alpha)
            results.append((src, dst, res))
        except Exception as exc:  # 批量任务不中断
            results.append((src, dst, exc))
        if progress:
            progress(i + 1, src, results[-1][2])
    return results


def fingerprint_stats(rgb: np.ndarray) -> dict:
    """给出可用于报告的基础统计（尺寸、亮度均值、纹理度）。"""
    y, _cb, _cr = imageio.to_ycbcr(rgb)
    return {
        "width": int(rgb.shape[1]),
        "height": int(rgb.shape[0]),
        "mean_luma": float(np.mean(y)),
        "luma_std": float(np.std(y)),
        "captured_at": datetime.now(timezone.utc).isoformat(),
    }
