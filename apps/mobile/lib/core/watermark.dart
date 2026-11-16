// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 移动端离线水印引擎：两级 Haar DWT + 4×4 分块 DCT + 归一化 AC 扩频 + RS(64,24)。
// 与 Python 参考实现（invismark/core/pipeline.py）算法同构、参数一致；随机数发生器不同，
// 因此「同一 seed 的码图案」两端不互认——跨端场景请统一用一侧实现。
//
// 为什么要在手机本地跑：独立部署时没有后端可调，嵌入/提取必须在本机完成。

import 'dart:math' as math;
import 'dart:typed_data';

import 'png_codec.dart';
import 'rs.dart';
import 'trace_codec.dart';

class EmbedOutcome {
  const EmbedOutcome({
    required this.image,
    required this.traceId,
    required this.psnr,
    required this.ssim,
    required this.blocksUsed,
    required this.blocksPerBit,
    required this.elapsedMs,
  });

  final ImageData image;
  final String traceId;
  final double psnr;
  final double ssim;
  final int blocksUsed;
  final int blocksPerBit;
  final double elapsedMs;
}

class ExtractOutcome {
  const ExtractOutcome({
    required this.found,
    this.trace,
    this.confidence = 0,
    this.corrected = 0,
    this.ber = 1,
    this.reason = '',
  });

  final bool found;
  final TraceCode? trace;
  final double confidence;
  final int corrected;
  final double ber;
  final String reason;
}

class WatermarkEngine {
  WatermarkEngine._();

  static const int baseLongEdge = 1600; // 移动端基准：内存与耗时约为 2400 的一半，k≈58 足够
  static const int minLongEdge = 800;
  static const double alpha = 0.60;
  static const double minAmplitude = 3.0;
  static const double maxAmplitude = 24.0;
  static const double minAcEnergy = 9.0;
  static const int bitsPerCodeword = 64 * 8;

  // ── 嵌入 ────────────────────────────────────────────────────

  static EmbedOutcome embed(ImageData source, TraceCode code, int seed) {
    final Stopwatch watch = Stopwatch()..start();
    final int h = source.height;
    final int w = source.width;
    if (math.min(h, w) < 64) {
      throw StateError('图片太小：${w}x$h');
    }
    if (math.max(h, w) < minLongEdge) {
      throw StateError('长边需 ≥ ${minLongEdge}px 才能可靠嵌入');
    }

    final _Ycc ycc = _toYcc(source);
    final List<int> dims = _baseDims(h, w);
    final int baseH = dims[0];
    final int baseW = dims[1];
    final Float32List yBase = _resize(ycc.y, w, h, baseW, baseH);

    final int level = _autoLevel(baseH, baseW);
    final List<Float32List> bands = <Float32List>[];
    Float32List ll = yBase;
    int cw = baseW;
    int ch = baseH;
    for (int i = 0; i < level; i++) {
      final _Bands b = _haarDwt(ll, cw, ch);
      bands.add(b.hl);
      bands.add(b.lh);
      bands.add(b.hh);
      ll = b.ll;
      cw = b.width;
      ch = b.height;
    }

    final int bw = cw ~/ 4;
    final int bh = ch ~/ 4;
    final int blocks = bw * bh;
    final int k = blocks ~/ bitsPerCodeword;
    if (k < 1) {
      throw StateError('基准分辨率过小，块数不足');
    }
    final int used = bitsPerCodeword * k;

    final List<int> codeword = ReedSolomon.encode(code.toBytes());
    final Uint8List rawBits = Uint8List(bitsPerCodeword);
    for (int i = 0; i < codeword.length; i++) {
      for (int b = 0; b < 8; b++) {
        rawBits[i * 8 + b] = (codeword[i] >> (7 - b)) & 1;
      }
    }
    final List<int> order = _scrambleOrder(seed);
    final Uint8List bits = Uint8List(bitsPerCodeword);
    for (int i = 0; i < bitsPerCodeword; i++) {
      bits[i] = rawBits[order[i]];
    }
    final Int8List signs = _spreadSigns(seed, used, k);

    final Float32List dct = _dctMatrix();
    final Float32List coef = Float32List(16);
    final double floorAmp = minAmplitude * math.pow(2.5, level - 1).toDouble();
    final double capAmp = maxAmplitude * math.pow(2.0, level - 1).toDouble();
    int blocksUsed = 0;

    for (int bi = 0; bi < used; bi++) {
      final int by = bi ~/ bw;
      final int bx = bi % bw;
      final int base = (by * 4) * cw + (bx * 4);
      _blockDctInto(ll, base, cw, dct, coef);
      double energy = 0;
      for (int r = 1; r < 4; r++) {
        for (int c = 1; c < 4; c++) {
          final double v = coef[r * 4 + c];
          energy += v * v;
        }
      }
      final int sign = signs[bi];
      if (sign == 0) continue;
      final double wanted = bits[bi % bitsPerCodeword] == 1 ? 1.0 : -1.0;
      final double amp = math.min(math.max(alpha * math.sqrt(energy), floorAmp), capAmp);
      coef[5] += wanted * sign * amp;
      if (energy > minAcEnergy) blocksUsed++;
      _blockIdct(ll, coef, base, cw, dct);
    }

    Float32List restored = ll;
    int rw = cw;
    int rh = ch;
    for (int i = level - 1; i >= 0; i--) {
      final int idx = i * 3;
      restored = _haarIdwt(restored, bands[idx], bands[idx + 1], bands[idx + 2], rw, rh);
      rw *= 2;
      rh *= 2;
    }

    final Float32List diff = Float32List(baseW * baseH);
    for (int i = 0; i < diff.length; i++) {
      diff[i] = restored[i] - yBase[i];
    }
    final Float32List diffFull = _resize(diff, baseW, baseH, w, h);
    final Uint8List out = Uint8List(w * h * 4);
    for (int i = 0, p = 0; i < w * h; i++, p += 4) {
      final double y = _clamp(ycc.y[i] + diffFull[i], 0, 255);
      final double cb = ycc.cb[i] - 128;
      final double cr = ycc.cr[i] - 128;
      final double r = y + 1.402 * cr;
      final double g = y - 0.344136 * cb - 0.714136 * cr;
      final double b = y + 1.772 * cb;
      out[p] = _clamp(r, 0, 255).round();
      out[p + 1] = _clamp(g, 0, 255).round();
      out[p + 2] = _clamp(b, 0, 255).round();
      out[p + 3] = 255;
    }

    final ImageData image = ImageData(width: w, height: h, rgba: out);
    return EmbedOutcome(
      image: image,
      traceId: code.hex,
      psnr: _psnr(source, image),
      ssim: _ssim(ycc.y, image, w, h),
      blocksUsed: blocksUsed,
      blocksPerBit: k,
      elapsedMs: watch.elapsedMicroseconds / 1000.0,
    );
  }

  // ── 提取 ────────────────────────────────────────────────────

  static ExtractOutcome extract(ImageData source, int seed) {
    final int h = source.height;
    final int w = source.width;
    final _Ycc ycc = _toYcc(source);
    final List<int> dims = _baseDims(h, w);
    final Float32List yBase = _resize(ycc.y, w, h, dims[1], dims[0]);
    final int level = _autoLevel(dims[0], dims[1]);
    Float32List current = yBase;
    int cw = dims[1];
    int ch = dims[0];
    for (int i = 0; i < level; i++) {
      final _Bands b = _haarDwt(current, cw, ch);
      current = b.ll;
      cw = b.width;
      ch = b.height;
    }
    final int bw = cw ~/ 4;
    final int bh = ch ~/ 4;
    final int k = (bw * bh) ~/ bitsPerCodeword;
    if (k < 1) {
      return const ExtractOutcome(found: false, reason: '图片过小，块数不足');
    }
    final int used = bitsPerCodeword * k;
    final Float32List coeffs = Float32List(used);
    final Float32List dct = _dctMatrix();
    final Float32List coef = Float32List(16);
    for (int bi = 0; bi < used; bi++) {
      final int by = bi ~/ bw;
      final int bx = bi % bw;
      final int base = (by * 4) * cw + (bx * 4);
      _blockDctInto(current, base, cw, dct, coef);
      coeffs[bi] = coef[5];
    }

    double sum = 0;
    for (int i = 0; i < used; i++) {
      sum += coeffs[i];
    }
    final double globalMean = sum / used;
    final Float32List bitSum = Float32List(bitsPerCodeword);
    final Int32List bitCount = Int32List(bitsPerCodeword);
    for (int bi = 0; bi < used; bi++) {
      final int b = bi % bitsPerCodeword;
      bitSum[b] += coeffs[bi];
      bitCount[b]++;
    }
    for (int b = 0; b < bitsPerCodeword; b++) {
      if (bitCount[b] > 0) {
        bitSum[b] /= bitCount[b];
      }
    }
    final Int8List signs = _spreadSigns(seed, used, k);
    final Float32List score = Float32List(bitsPerCodeword);
    for (int bi = 0; bi < used; bi++) {
      final int b = bi % bitsPerCodeword;
      score[b] += (coeffs[bi] - globalMean - bitSum[b]) * signs[bi];
    }

    final Uint8List bits = Uint8List(bitsPerCodeword);
    for (int i = 0; i < bitsPerCodeword; i++) {
      bits[i] = score[i] > 0 ? 1 : 0;
    }
    final List<int> order = _scrambleOrder(seed);
    final Uint8List raw = Uint8List(bitsPerCodeword);
    for (int i = 0; i < bitsPerCodeword; i++) {
      raw[order[i]] = bits[i];
    }
    final List<int> codeword = List<int>.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      int b = 0;
      for (int j = 0; j < 8; j++) {
        b = (b << 1) | raw[i * 8 + j];
      }
      codeword[i] = b;
    }
    final RSResult rs = ReedSolomon.decode(codeword);
    if (!rs.ok || rs.payload == null) {
      return ExtractOutcome(found: false, reason: rs.message, ber: rs.ber);
    }
    try {
      final TraceCode trace = TraceCode.fromBytes(rs.payload!);
      return ExtractOutcome(
        found: true,
        trace: trace,
        confidence: (1 - rs.corrected / ReedSolomon.n).clamp(0.0, 1.0),
        corrected: rs.corrected,
        ber: rs.ber,
      );
    } catch (error) {
      return ExtractOutcome(found: false, reason: '追溯码校验失败：$error', ber: rs.ber);
    }
  }

  // ── 基础工具 ────────────────────────────────────────────────

  static double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  static List<int> _baseDims(int h, int w) {
    final double scale = baseLongEdge / math.max(h, w);
    int nh = math.max(16, (h * scale).round());
    int nw = math.max(16, (w * scale).round());
    const int multiple = 16;
    nh = math.max(multiple, (nh / multiple).round() * multiple);
    nw = math.max(multiple, (nw / multiple).round() * multiple);
    return <int>[nh, nw];
  }

  static int _autoLevel(int baseH, int baseW) {
    for (final int lvl in <int>[2, 1]) {
      final int blocks = (baseH ~/ (1 << lvl) ~/ 4) * (baseW ~/ (1 << lvl) ~/ 4);
      if (blocks ~/ bitsPerCodeword >= 8) return lvl;
    }
    return 1;
  }

  static Float32List _dctMatrix() {
    final Float32List m = Float32List(16);
    for (int k = 0; k < 4; k++) {
      final double ck = k == 0 ? math.sqrt(0.25) : math.sqrt(0.5);
      for (int x = 0; x < 4; x++) {
        m[k * 4 + x] = ck * math.cos(math.pi * (2 * x + 1) * k / 8.0);
      }
    }
    return m;
  }

  static void _blockDctInto(Float32List plane, int base, int width, Float32List d, Float32List out) {
    for (int u = 0; u < 4; u++) {
      for (int v = 0; v < 4; v++) {
        double s = 0;
        for (int y = 0; y < 4; y++) {
          final int row = base + y * width;
          for (int x = 0; x < 4; x++) {
            s += d[u * 4 + y] * plane[row + x] * d[v * 4 + x];
          }
        }
        out[u * 4 + v] = s;
      }
    }
  }

  static void _blockIdct(Float32List plane, Float32List coef, int base, int width, Float32List d) {
    for (int y = 0; y < 4; y++) {
      final int row = base + y * width;
      for (int x = 0; x < 4; x++) {
        double s = 0;
        for (int u = 0; u < 4; u++) {
          for (int v = 0; v < 4; v++) {
            s += d[u * 4 + y] * coef[u * 4 + v] * d[v * 4 + x];
          }
        }
        plane[row + x] = s;
      }
    }
  }

  static Float32List _resize(Float32List src, int sw, int sh, int dw, int dh) {
    if (sw == dw && sh == dh) return Float32List.fromList(src);
    final Float32List out = Float32List(dw * dh);
    final double scaleX = sw / dw;
    final double scaleY = sh / dh;
    for (int y = 0; y < dh; y++) {
      final double sy = (y + 0.5) * scaleY - 0.5;
      int y0 = sy.floor();
      final double wy = sy - y0;
      if (y0 < 0) y0 = 0;
      final int y1 = math.min(y0 + 1, sh - 1);
      for (int x = 0; x < dw; x++) {
        final double sx = (x + 0.5) * scaleX - 0.5;
        int x0 = sx.floor();
        final double wx = sx - x0;
        if (x0 < 0) x0 = 0;
        final int x1 = math.min(x0 + 1, sw - 1);
        final double top = src[y0 * sw + x0] * (1 - wx) + src[y0 * sw + x1] * wx;
        final double bottom = src[y1 * sw + x0] * (1 - wx) + src[y1 * sw + x1] * wx;
        out[y * dw + x] = top * (1 - wy) + bottom * wy;
      }
    }
    return out;
  }

  static _Bands _haarDwt(Float32List y, int w, int h) {
    final int w2 = w ~/ 2;
    final int h2 = h ~/ 2;
    final Float32List ll = Float32List(w2 * h2);
    final Float32List hl = Float32List(w2 * h2);
    final Float32List lh = Float32List(w2 * h2);
    final Float32List hh = Float32List(w2 * h2);
    for (int y2 = 0; y2 < h2; y2++) {
      final int r0 = (y2 * 2) * w;
      final int r1 = (y2 * 2 + 1) * w;
      for (int x2 = 0; x2 < w2; x2++) {
        final int x0 = x2 * 2;
        final double a = y[r0 + x0];
        final double b = y[r0 + x0 + 1];
        final double c = y[r1 + x0];
        final double d = y[r1 + x0 + 1];
        final int idx = y2 * w2 + x2;
        ll[idx] = (a + b + c + d) * 0.5;
        hl[idx] = (a - b + c - d) * 0.5;
        lh[idx] = (a + b - c - d) * 0.5;
        hh[idx] = (a - b - c + d) * 0.5;
      }
    }
    return _Bands(ll: ll, hl: hl, lh: lh, hh: hh, width: w2, height: h2);
  }

  static Float32List _haarIdwt(
    Float32List ll,
    Float32List hl,
    Float32List lh,
    Float32List hh,
    int w2,
    int h2,
  ) {
    final int w = w2 * 2;
    final Float32List out = Float32List(w * h2 * 2);
    for (int y2 = 0; y2 < h2; y2++) {
      final int r0 = (y2 * 2) * w;
      final int r1 = (y2 * 2 + 1) * w;
      for (int x2 = 0; x2 < w2; x2++) {
        final int idx = y2 * w2 + x2;
        final double a = ll[idx];
        final double b = hl[idx];
        final double c = lh[idx];
        final double d = hh[idx];
        out[r0 + x2 * 2] = (a + b + c + d) * 0.5;
        out[r0 + x2 * 2 + 1] = (a - b + c - d) * 0.5;
        out[r1 + x2 * 2] = (a + b - c - d) * 0.5;
        out[r1 + x2 * 2 + 1] = (a - b - c + d) * 0.5;
      }
    }
    return out;
  }

  // ── 随机数与扩频 ────────────────────────────────────────────

  static List<int> _scrambleOrder(int seed) {
    final _Rng rng = _Rng(seed ^ 0x5EED5EED);
    final List<int> order = List<int>.generate(bitsPerCodeword, (int i) => i);
    for (int i = order.length - 1; i > 0; i--) {
      final int j = rng.nextInt(i + 1);
      final int t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    return order;
  }

  static Int8List _spreadSigns(int seed, int used, int k) {
    final int keep = 2 * (k ~/ 2);
    final List<int> base = List<int>.filled(k, 0);
    for (int j = 0; j < keep ~/ 2; j++) {
      base[j] = -1;
    }
    for (int j = keep ~/ 2; j < keep; j++) {
      base[j] = 1;
    }
    final _Rng rng = _Rng(seed ^ 0xA11CE);
    final Int8List signs = Int8List(used);
    final List<List<int>> rows = List<List<int>>.generate(bitsPerCodeword, (int b) {
      return List<int>.from(base);
    });
    for (final List<int> r in rows) {
      for (int i = r.length - 1; i > 0; i--) {
        final int j = rng.nextInt(i + 1);
        final int t = r[i];
        r[i] = r[j];
        r[j] = t;
      }
    }
    for (int j = 0; j < k; j++) {
      for (int b = 0; b < bitsPerCodeword; b++) {
        final int idx = j * bitsPerCodeword + b;
        if (idx < used) signs[idx] = rows[b][j];
      }
    }
    return signs;
  }

  static _Ycc _toYcc(ImageData image) {
    final int n = image.width * image.height;
    final Float32List y = Float32List(n);
    final Float32List cb = Float32List(n);
    final Float32List cr = Float32List(n);
    final Uint8List rgba = image.rgba;
    for (int i = 0, p = 0; i < n; i++, p += 4) {
      final double r = rgba[p].toDouble();
      final double g = rgba[p + 1].toDouble();
      final double b = rgba[p + 2].toDouble();
      y[i] = 0.299 * r + 0.587 * g + 0.114 * b;
      cb[i] = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b;
      cr[i] = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    }
    return _Ycc(y: y, cb: cb, cr: cr);
  }

  static double _psnr(ImageData a, ImageData b) {
    double se = 0;
    for (int i = 0; i < a.rgba.length; i += 4) {
      for (int c = 0; c < 3; c++) {
        final double d = (a.rgba[i + c] - b.rgba[i + c]).toDouble();
        se += d * d;
      }
    }
    final double mse = se / (a.width * a.height * 3);
    if (mse <= 0) return double.infinity;
    return 10 * (math.log(255 * 255 / mse) / math.ln10);
  }

  static double _ssim(Float32List ya, ImageData b, int w, int h) {
    const int win = 8;
    final int bw = w ~/ win;
    final int bh = h ~/ win;
    if (bw == 0 || bh == 0) return 1;
    const double c1 = 6.5025;
    const double c2 = 58.5225;
    final Float32List yb = Float32List(w * h);
    for (int i = 0, p = 0; i < w * h; i++, p += 4) {
      yb[i] = 0.299 * b.rgba[p] + 0.587 * b.rgba[p + 1] + 0.114 * b.rgba[p + 2];
    }
    double total = 0;
    int count = 0;
    const int n = win * win;
    for (int by = 0; by < bh; by++) {
      for (int bx = 0; bx < bw; bx++) {
        double ma = 0;
        double mb = 0;
        for (int y = 0; y < win; y++) {
          final int row = (by * win + y) * w + bx * win;
          for (int x = 0; x < win; x++) {
            ma += ya[row + x];
            mb += yb[row + x];
          }
        }
        ma /= n;
        mb /= n;
        double va = 0;
        double vb = 0;
        double cov = 0;
        for (int y = 0; y < win; y++) {
          final int row = (by * win + y) * w + bx * win;
          for (int x = 0; x < win; x++) {
            final double da = ya[row + x] - ma;
            final double db = yb[row + x] - mb;
            va += da * da;
            vb += db * db;
            cov += da * db;
          }
        }
        va /= n;
        vb /= n;
        cov /= n;
        total += ((2 * ma * mb + c1) * (2 * cov + c2)) /
            ((ma * ma + mb * mb + c1) * (va + vb + c2));
        count++;
      }
    }
    return count == 0 ? 1 : total / count;
  }
}

class _Ycc {
  const _Ycc({required this.y, required this.cb, required this.cr});
  final Float32List y;
  final Float32List cb;
  final Float32List cr;
}

class _Bands {
  const _Bands({
    required this.ll,
    required this.hl,
    required this.lh,
    required this.hh,
    required this.width,
    required this.height,
  });
  final Float32List ll;
  final Float32List hl;
  final Float32List lh;
  final Float32List hh;
  final int width;
  final int height;
}

/// splitmix64：确定、跨平台一致的伪随机源（不依赖 numpy）。
class _Rng {
  _Rng(int seed) : _state = seed & 0x7FFFFFFFFFFFFFFF;

  int _state;

  int _next() {
    _state = (_state + 0x9E3779B97F4A7C15) & 0x7FFFFFFFFFFFFFFF;
    int z = _state;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0x7FFFFFFFFFFFFFFF;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0x7FFFFFFFFFFFFFFF;
    return (z ^ (z >> 31)) & 0x7FFFFFFFFFFFFFFF;
  }

  int nextInt(int max) => _next() % max;
}
