// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 鲁棒性回归：真实照片常见「大片平滑天空 + 少量细节」。
// 历史 bug：移动端基准长边降到 1600 时 k≈8，这类内容检不出；
// 这里用低纹理合成图锁住默认基准（2400）下的嵌入→提取闭环。

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invismark_mobile/core/png_codec.dart';
import 'package:invismark_mobile/core/trace_codec.dart';
import 'package:invismark_mobile/core/watermark.dart';

ImageData lowTexture(int width, int height) {
  final math.Random rng = math.Random(3);
  final Uint8List rgba = Uint8List(width * height * 4);
  int p = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final double sky = 200 + 8 * (y / height) + 2 * math.sin(x / 400.0);
      final bool detail = y > height * 0.75;
      final int v = (sky + (detail ? rng.nextDouble() * 60 : 0)).round().clamp(0, 255);
      rgba[p++] = v;
      rgba[p++] = (v * 0.98).round().clamp(0, 255);
      rgba[p++] = (v * 0.95).round().clamp(0, 255);
      rgba[p++] = 255;
    }
  }
  return ImageData(width: width, height: height, rgba: rgba);
}

void main() {
  test('默认基准可以承受低纹理照片', () {
    expect(WatermarkEngine.baseLongEdge, 2400);
    final ImageData img = lowTexture(2400, 1800);
    final TraceCode code = TraceCode.newCustom(text: '轻云落梦');
    final EmbedOutcome embed = WatermarkEngine.embed(img, code, 20261116);
    final Uint8List png = PngCodec.encode(embed.image);
    final ExtractOutcome got = WatermarkEngine.extract(PngCodec.decode(png), 20261116);
    expect(got.found, isTrue, reason: got.reason);
    expect(got.trace?.customText, '轻云落梦');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
