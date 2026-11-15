// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// GF(2^8) 有限域运算（本原多项式 0x11D，生成元 α=2）。
// 与 Python 版 invismark/core/gf256.py 同一套参数，用于移动端离线引擎的 RS 纠错。

class GF256 {
  GF256._();

  static const int primitivePoly = 0x11D;

  static final List<int> exp = List<int>.filled(512, 0);
  static final List<int> log = List<int>.filled(256, 0);
  static bool _ready = false;

  static void ensure() {
    if (_ready) return;
    int x = 1;
    for (int i = 0; i < 255; i++) {
      exp[i] = x;
      log[x] = i;
      x <<= 1;
      if ((x & 0x100) != 0) x ^= primitivePoly;
    }
    for (int i = 255; i < 512; i++) {
      exp[i] = exp[i - 255];
    }
    log[0] = 0;
    _ready = true;
  }

  static int mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return exp[log[a] + log[b]];
  }

  static int div(int a, int b) {
    if (b == 0) throw ArgumentError('GF(256) division by zero');
    if (a == 0) return 0;
    int e = log[a] - log[b];
    if (e < 0) e += 255;
    return exp[e];
  }

  static int pow(int base, int exponent) {
    if (exponent == 0) return 1;
    if (base == 0) return 0;
    int e = (log[base] * exponent) % 255;
    if (e < 0) e += 255;
    return exp[e];
  }

  static int inverse(int a) {
    if (a == 0) throw ArgumentError('GF(256) inverse of zero');
    return exp[255 - log[a]];
  }

  static int polyEval(List<int> poly, int x) {
    int y = 0;
    for (int c in poly) {
      y = mul(y, x) ^ c;
    }
    return y;
  }

  static List<int> polyMul(List<int> p, List<int> q) {
    final List<int> out = List<int>.filled(p.length + q.length - 1, 0);
    for (int i = 0; i < p.length; i++) {
      final int a = p[i];
      if (a == 0) continue;
      for (int j = 0; j < q.length; j++) {
        out[i + j] ^= mul(a, q[j]);
      }
    }
    return out;
  }

  static List<int> polyAdd(List<int> p, List<int> q) {
    final int n = p.length > q.length ? p.length : q.length;
    final List<int> out = List<int>.filled(n, 0);
    for (int i = 0; i < p.length; i++) {
      out[n - p.length + i] = p[i];
    }
    for (int i = 0; i < q.length; i++) {
      out[n - q.length + i] ^= q[i];
    }
    return out;
  }
}
