// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// Reed–Solomon RS(64,24)：24 字节载荷 + 40 字节校验，可纠 20 字节错误。
// 由 RS(255,215) 缩短而来；解码走 Berlekamp–Massey + Chien + Forney。
// 与 Python 版 invismark/core/rs.py 算法一致（参数相同）。

import 'gf256.dart';

class RSResult {
  const RSResult({
    required this.ok,
    required this.payload,
    required this.corrected,
    required this.message,
  });

  final bool ok;
  final List<int>? payload;
  final int corrected;
  final String message;

  double get ber => corrected / 64.0;
}

class ReedSolomon {
  ReedSolomon._();

  static const int nsym = 40;
  static const int k = 24;
  static const int n = 64;
  static const int fullN = 255;
  static const int fcr = 0;
  static const int generator = 2;

  static List<int>? _gen;

  static List<int> get gen {
    GF256.ensure();
    final List<int>? cached = _gen;
    if (cached != null) return cached;
    List<int> g = <int>[1];
    for (int i = 0; i < nsym; i++) {
      g = GF256.polyMul(g, <int>[1, GF256.pow(generator, i + fcr)]);
    }
    _gen = g;
    return g;
  }

  static List<int> _polyScale(List<int> p, int x) {
    if (x == 0) return List<int>.filled(p.length, 0);
    return p.map((int c) => GF256.mul(c, x)).toList();
  }

  /// 多项式带余除法，返回 (商, 余数)
  static (List<int>, List<int>) _polyDiv(List<int> dividend, List<int> divisor) {
    final List<int> out = List<int>.from(dividend);
    final List<int> quot = List<int>.filled(dividend.length - divisor.length + 1, 0);
    for (int i = 0; i < quot.length; i++) {
      final int coef = out[i];
      if (coef != 0) {
        for (int j = 1; j < divisor.length; j++) {
          if (divisor[j] != 0) {
            out[i + j] ^= GF256.mul(divisor[j], coef);
          }
        }
      }
      quot[i] = coef;
    }
    return (quot, out.sublist(quot.length));
  }

  /// 24 字节 → 64 字节系统码字
  static List<int> encode(List<int> payload) {
    if (payload.length != k) {
      throw ArgumentError('payload must be exactly $k bytes');
    }
    GF256.ensure();
    final List<int> msg = <int>[...payload, ...List<int>.filled(nsym, 0)];
    final List<int> g = gen;
    for (int i = 0; i < k; i++) {
      final int coef = msg[i];
      if (coef != 0) {
        for (int j = 0; j < g.length; j++) {
          msg[i + j] ^= GF256.mul(g[j], coef);
        }
      }
    }
    return <int>[...payload, ...msg.sublist(k)];
  }

  static List<int> _calcSyndromes(List<int> msg) {
    final List<int> out = <int>[0];
    for (int i = 0; i < nsym; i++) {
      out.add(GF256.polyEval(msg, GF256.pow(generator, i + fcr)));
    }
    return out;
  }

  static List<int> _findErrorLocator(List<int> synd) {
    List<int> errLoc = <int>[1];
    List<int> oldLoc = <int>[1];
    for (int i = 0; i < nsym; i++) {
      final int kk = i + 1;
      int delta = synd[kk];
      for (int j = 1; j < errLoc.length; j++) {
        delta ^= GF256.mul(errLoc[errLoc.length - (j + 1)], synd[kk - j]);
      }
      oldLoc = <int>[...oldLoc, 0];
      if (delta != 0) {
        if (oldLoc.length > errLoc.length) {
          final List<int> newLoc = _polyScale(oldLoc, delta);
          oldLoc = _polyScale(errLoc, GF256.inverse(delta));
          errLoc = newLoc;
        }
        errLoc = GF256.polyAdd(errLoc, _polyScale(oldLoc, delta));
      }
    }
    while (errLoc.isNotEmpty && errLoc[0] == 0) {
      errLoc.removeAt(0);
    }
    return errLoc;
  }

  static List<int> _findErrorPositions(List<int> errLoc, int nmess) {
    final int errs = errLoc.length - 1;
    final List<int> positions = <int>[];
    for (int i = 0; i < nmess; i++) {
      if (GF256.polyEval(errLoc, GF256.pow(generator, i)) == 0) {
        positions.add(nmess - 1 - i);
      }
    }
    if (positions.length != errs) {
      throw StateError('error locator mismatch');
    }
    return positions;
  }

  static List<int> _findErrataLocator(List<int> coefPos) {
    List<int> eLoc = <int>[1];
    for (final int pos in coefPos) {
      eLoc = GF256.polyMul(eLoc, GF256.polyAdd(<int>[1], <int>[GF256.pow(generator, pos), 0]));
    }
    return eLoc;
  }

  static List<int> _findErrorEvaluator(List<int> synd, List<int> errLoc, int nsymArg) {
    final List<int> product = GF256.polyMul(synd, errLoc);
    final (_, List<int> remainder) =
        _polyDiv(product, <int>[1, ...List<int>.filled(nsymArg + 1, 0)]);
    return remainder;
  }

  static List<int> _correctErrata(List<int> msg, List<int> synd, List<int> errPos) {
    final List<int> coefPos =
        errPos.map((int p) => msg.length - 1 - p).toList();
    final List<int> errLoc = _findErrataLocator(coefPos);
    final List<int> errEval = _findErrorEvaluator(synd.reversed.toList(), errLoc, errLoc.length - 1)
        .reversed
        .toList();
    final List<int> xs = coefPos.map((int p) => GF256.pow(generator, p)).toList();
    final List<int> e = List<int>.filled(msg.length, 0);
    for (int i = 0; i < xs.length; i++) {
      final int xi = xs[i];
      final int xiInv = GF256.inverse(xi);
      int denom = 1;
      for (int j = 0; j < xs.length; j++) {
        if (i != j) {
          denom = GF256.mul(denom, 1 ^ GF256.mul(xiInv, xs[j]));
        }
      }
      int y = GF256.polyEval(errEval.reversed.toList(), xiInv);
      y = GF256.mul(GF256.pow(xi, 1 - fcr), y);
      e[errPos[i]] = GF256.div(y, denom);
    }
    return GF256.polyAdd(msg, e);
  }

  /// 64 字节 → 24 字节；失败不抛异常
  static RSResult decode(List<int> codeword) {
    if (codeword.length != n) {
      return const RSResult(ok: false, payload: null, corrected: 0, message: 'codeword must be 64 bytes');
    }
    GF256.ensure();
    final List<int> full = <int>[...List<int>.filled(fullN - n, 0), ...codeword];
    final List<int> synd = _calcSyndromes(full);
    if (synd.reduce((int a, int b) => a > b ? a : b) == 0) {
      return RSResult(ok: true, payload: codeword.sublist(0, k), corrected: 0, message: '');
    }
    try {
      final List<int> errLoc = _findErrorLocator(synd);
      final int errs = errLoc.length - 1;
      if (errs == 0) {
        return const RSResult(ok: false, payload: null, corrected: 0, message: 'locator degree 0');
      }
      if (errs > nsym ~/ 2) {
        return RSResult(ok: false, payload: null, corrected: 0, message: 'too many errors: $errs');
      }
      final List<int> errPos = _findErrorPositions(errLoc.reversed.toList(), fullN);
      final List<int> corrected = _correctErrata(full, synd, errPos);
      if (_calcSyndromes(corrected).reduce((int a, int b) => a > b ? a : b) != 0) {
        return const RSResult(ok: false, payload: null, corrected: 0, message: 'syndrome check failed');
      }
      final List<int> fixed = corrected.sublist(fullN - n);
      return RSResult(
        ok: true,
        payload: fixed.sublist(0, k),
        corrected: errPos.length,
        message: '',
      );
    } catch (error) {
      return RSResult(ok: false, payload: null, corrected: 0, message: '$error');
    }
  }
}
