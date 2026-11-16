import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invismark_mobile/core/trace_codec.dart';
import 'package:invismark_mobile/core/png_codec.dart';
import 'package:invismark_mobile/core/watermark.dart';

ImageData synth(int width, int height) {
  final math.Random rng = math.Random(7);
  final Uint8List rgba = Uint8List(width * height * 4);
  int p = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final double base = 80 + 120 * (x / width) + 30 * (y / height);
      rgba[p++] = (base + rng.nextDouble() * 20).round().clamp(0, 255);
      rgba[p++] = (base * 0.85 + 20).round().clamp(0, 255);
      rgba[p++] = (base * 0.7 + 40).round().clamp(0, 255);
      rgba[p++] = 255;
    }
  }
  return ImageData(width: width, height: height, rgba: rgba);
}

void main() {
  test('1600px 嵌入/提取耗时', () {
    final ImageData img = synth(1600, 1200);
    final TraceCode code = TraceCode.newCode(resourceCode: 'F13241', userIndex: 1);
    final Stopwatch w1 = Stopwatch()..start();
    final EmbedOutcome embed = WatermarkEngine.embed(img, code, 12345);
    w1.stop();
    final Stopwatch w2 = Stopwatch()..start();
    final ExtractOutcome extract = WatermarkEngine.extract(embed.image, 12345);
    w2.stop();
    // ignore: avoid_print
    print('EMBED ${w1.elapsedMilliseconds}ms psnr=${embed.psnr.toStringAsFixed(2)} '
        'k=${embed.blocksPerBit} | EXTRACT ${w2.elapsedMilliseconds}ms found=${extract.found}');
    expect(extract.found, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
