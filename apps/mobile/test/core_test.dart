// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 移动端离线引擎的核心测试：RS、追溯码、PNG、水印嵌入/提取。
// 运行：flutter test test/core_test.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:invismark_mobile/core/png_codec.dart';
import 'package:invismark_mobile/core/rs.dart';
import 'package:invismark_mobile/core/trace_codec.dart';
import 'package:invismark_mobile/core/watermark.dart';

ImageData synth(int width, int height, {int seed = 7}) {
  final math.Random rng = math.Random(seed);
  final Uint8List rgba = Uint8List(width * height * 4);
  int p = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final double base = 80 + 120 * (x / width) + 30 * (y / height);
      int r = (base + rng.nextDouble() * 30 - 15).round();
      int g = (base * 0.85 + 20 + rng.nextDouble() * 30 - 15).round();
      int b = (base * 0.7 + 40 + rng.nextDouble() * 30 - 15).round();
      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);
      rgba[p++] = r;
      rgba[p++] = g;
      rgba[p++] = b;
      rgba[p++] = 255;
    }
  }
  return ImageData(width: width, height: height, rgba: rgba);
}

void main() {
  group('RS(64,24)', () {
    test('编码长度与系统码性质', () {
      final List<int> payload = List<int>.generate(24, (int i) => i * 7 % 256);
      final List<int> code = ReedSolomon.encode(payload);
      expect(code.length, 64);
      expect(code.sublist(0, 24), payload);
    });

    test('可纠 20 字节错误', () {
      final math.Random rng = math.Random(11);
      for (int trial = 0; trial < 10; trial++) {
        final List<int> payload = List<int>.generate(24, (_) => rng.nextInt(256));
        final List<int> code = List<int>.from(ReedSolomon.encode(payload));
        final int errors = 1 + rng.nextInt(20);
        final Set<int> positions = <int>{};
        while (positions.length < errors) {
          positions.add(rng.nextInt(64));
        }
        for (final int pos in positions) {
          code[pos] ^= 1 + rng.nextInt(255);
        }
        final RSResult result = ReedSolomon.decode(code);
        expect(result.ok, isTrue, reason: 'errors=$errors');
        expect(result.payload, payload);
        expect(result.corrected, errors);
      }
    });

    test('超限错误被拒绝', () {
      final math.Random rng = math.Random(3);
      final List<int> payload = List<int>.generate(24, (int i) => i);
      final List<int> code = List<int>.from(ReedSolomon.encode(payload));
      final Set<int> positions = <int>{};
      while (positions.length < 26) {
        positions.add(rng.nextInt(64));
      }
      for (final int pos in positions) {
        code[pos] ^= 1 + rng.nextInt(255);
      }
      final RSResult result = ReedSolomon.decode(code);
      // 超过 20 字节（t=20）不可纠正：要么明确失败，要么绝不能恢复出原载荷
      expect(result.ok && result.payload == null, isFalse);
      if (result.ok) {
        expect(result.payload, isNot(payload));
      }
    });
  });

  group('追溯码', () {
    test('编码/解码往返', () {
      final TraceCode code = TraceCode.newCode(
        resourceCode: 'F13241',
        userIndex: 7,
        embeddedAt: DateTime.utc(2026, 11, 15, 9, 20),
        serial: 42,
      );
      final List<int> bytes = code.toBytes();
      expect(bytes.length, 24);
      final TraceCode back = TraceCode.fromBytes(bytes);
      expect(back.resourceCode, 'F13241');
      expect(back.userIndex, 7);
      expect(back.serial, 42);
      expect(back.hex, code.hex);
    });

    test('CRC 损坏会被拒绝', () {
      final List<int> bytes = TraceCode.newCode(resourceCode: 'AB12', userIndex: 1).toBytes();
      bytes[5] ^= 1;
      expect(() => TraceCode.fromBytes(bytes), throwsFormatException);
    });

    test('自定义文本 v2 往返', () {
      final TraceCode code = TraceCode.newCustom(text: '张三-内部', serial: 9);
      final List<int> bytes = code.toBytes();
      expect(bytes.length, 24);
      expect(bytes[0], TraceCode.versionCustom);
      final TraceCode back = TraceCode.fromBytes(bytes);
      expect(back.customText, '张三-内部');
      expect(back.serial, 9);
      expect(back.isCustom, isTrue);
    });

    test('自定义文本超长被拒绝', () {
      expect(() => TraceCode.newCustom(text: '这个文本肯定超过十三个字节'), throwsFormatException);
    });
  });

  group('PNG 编解码', () {
    test('往返像素一致', () {
      final ImageData img = synth(64, 48);
      final Uint8List png = PngCodec.encode(img);
      expect(PngCodec.isPng(png), isTrue);
      final ImageData back = PngCodec.decode(png);
      expect(back.width, 64);
      expect(back.height, 48);
      expect(back.rgba, img.rgba);
    });
  });

  group('水印引擎', () {
    test('嵌入后提取出同一追溯码', () {
      final ImageData img = synth(800, 600);
      final TraceCode code = TraceCode.newCode(resourceCode: 'F13241', userIndex: 7);
      final EmbedOutcome embed = WatermarkEngine.embed(img, code, 20260115);
      expect(embed.psnr, greaterThan(35));
      expect(embed.traceId, code.hex);

      final ExtractOutcome extract = WatermarkEngine.extract(embed.image, 20260115);
      expect(extract.found, isTrue, reason: extract.reason);
      expect(extract.trace?.resourceCode, 'F13241');
      expect(extract.trace?.userIndex, 7);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('无水印图不会误报', () {
      final ImageData img = synth(800, 600, seed: 99);
      final ExtractOutcome extract = WatermarkEngine.extract(img, 20260115);
      expect(extract.found, isFalse);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('错误 seed 提取不到', () {
      final ImageData img = synth(800, 600);
      final TraceCode code = TraceCode.newCode(resourceCode: 'ZZZZZZ', userIndex: 3);
      final EmbedOutcome embed = WatermarkEngine.embed(img, code, 123);
      final ExtractOutcome extract = WatermarkEngine.extract(embed.image, 124);
      expect(extract.found, isFalse);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
