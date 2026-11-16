// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 回归测试：完整的 App 内本地引擎路径（LocalEngine）——自定义内容嵌入→提取。
// 用 mock 的 MethodChannel 模拟原生 prefs，不需要真机。

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invismark_mobile/core/png_codec.dart';
import 'package:invismark_mobile/services/local_engine.dart';

ImageData synth(int width, int height) {
  final math.Random rng = math.Random(7);
  final Uint8List rgba = Uint8List(width * height * 4);
  int p = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final double base = 90 + 100 * (x / width) + 40 * (y / height);
      rgba[p++] = (base + rng.nextDouble() * 18).round().clamp(0, 255);
      rgba[p++] = (base * 0.9 + 15).round().clamp(0, 255);
      rgba[p++] = (base * 0.75 + 30).round().clamp(0, 255);
      rgba[p++] = 255;
    }
  }
  return ImageData(width: width, height: height, rgba: rgba);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Map<String, String> prefs = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('invismark/media'),
    (MethodCall call) async {
      switch (call.method) {
        case 'getPrefs':
          return Map<String, String>.from(prefs);
        case 'setPref':
          final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
          prefs['${args['key']}'] = '${args['value']}';
          return true;
      }
      return null;
    },
  );

  test('LocalEngine：自定义内容嵌入后能提取回来', () async {
    final Uint8List source = PngCodec.encode(synth(1600, 1200));
    final LocalEmbedResult embed = await LocalEngine.embed(source, customText: '测试-2026');
    expect(embed.customText, '测试-2026');

    final LocalExtractResult got = await LocalEngine.extract(embed.pngBytes);
    expect(got.found, isTrue, reason: got.reason);
    expect(got.trace?.customText, '测试-2026');
    expect(got.trace?.hex, embed.traceId);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('LocalEngine：标准追溯码仍可用', () async {
    final Uint8List source = PngCodec.encode(synth(1200, 900));
    final LocalEmbedResult embed = await LocalEngine.embed(source);
    final LocalExtractResult got = await LocalEngine.extract(embed.pngBytes);
    expect(got.found, isTrue, reason: got.reason);
    expect(got.trace?.isCustom, isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
