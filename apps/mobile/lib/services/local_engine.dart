// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 本地离线引擎：手机端独立运行时的嵌入/提取入口。
// 图片解码：PNG 走自研纯 Dart 解码器；其它格式（JPEG/WebP）走 Flutter 引擎解码。
// 计算放到独立 isolate，避免 2400px 图片处理时卡 UI。

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;


import '../core/png_codec.dart';
import '../core/trace_codec.dart';
import '../core/watermark.dart';
import 'native_media.dart';

class LocalEmbedResult {
  const LocalEmbedResult({
    required this.pngBytes,
    required this.traceId,
    required this.resourceCode,
    required this.psnr,
    required this.ssim,
    required this.elapsedMs,
  });

  final Uint8List pngBytes;
  final String traceId;
  final String resourceCode;
  final double psnr;
  final double ssim;
  final double elapsedMs;
}

class LocalExtractResult {
  const LocalExtractResult({
    required this.found,
    this.trace,
    this.confidence = 0,
    this.corrected = 0,
    this.reason = '',
    this.elapsedMs = 0,
  });

  final bool found;
  final TraceCode? trace;
  final double confidence;
  final int corrected;
  final String reason;
  final double elapsedMs;
}

class LocalEngine {
  LocalEngine._();

  static const String seedKey = 'localSeed';
  static const String serialKey = 'localSerial';

  /// 首次使用时生成 31 位随机 seed 并落到本地设置；之后固定不变。
  static Future<int> ensureSeed() async {
    final Map<String, String> prefs = await NativeMedia.loadPrefs();
    final String? raw = prefs[seedKey];
    if (raw != null) {
      final int? parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    final int seed = math.Random.secure().nextInt(1 << 30) + 1;
    await NativeMedia.savePref(seedKey, '$seed');
    return seed;
  }

  static Future<int> _nextSerial() async {
    final Map<String, String> prefs = await NativeMedia.loadPrefs();
    final int current = int.tryParse(prefs[serialKey] ?? '0') ?? 0;
    await NativeMedia.savePref(serialKey, '${current + 1}');
    return current + 1;
  }

  /// 解码任意图片为 RGBA
  static Future<ImageData> decodeImage(Uint8List bytes) async {
    if (PngCodec.isPng(bytes)) {
      return PngCodec.decode(bytes);
    }
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('图片解码失败');
    }
    final ImageData image = ImageData(
      width: frame.image.width,
      height: frame.image.height,
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    frame.image.dispose();
    codec.dispose();
    return image;
  }

  static String _randomResourceCode() {
    const String alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final math.Random rng = math.Random.secure();
    final String body = List<String>.generate(
      5,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
    return 'F$body';
  }

  /// 本地嵌入：不联网，结果直接落在手机上。
  static Future<LocalEmbedResult> embed(Uint8List bytes, {String? resourceCode}) async {
    final ImageData source = await decodeImage(bytes);
    final int seed = await ensureSeed();
    final int serial = await _nextSerial();
    final String code = (resourceCode == null || resourceCode.trim().isEmpty)
        ? _randomResourceCode()
        : resourceCode.trim();
    final TraceCode trace = TraceCode.newCode(
      resourceCode: code,
      userIndex: 1,
      serial: serial,
    );
    final _EmbedPayload payload = _EmbedPayload(
      rgba: source.rgba,
      width: source.width,
      height: source.height,
      traceBytes: trace.toBytes(),
      seed: seed,
    );
    final _EmbedReply reply = await Isolate.run(() => _embedInIsolate(payload));
    final Uint8List png = PngCodec.encode(
      ImageData(width: reply.width, height: reply.height, rgba: reply.rgba),
    );
    return LocalEmbedResult(
      pngBytes: png,
      traceId: trace.hex,
      resourceCode: trace.resourceCode,
      psnr: reply.psnr,
      ssim: reply.ssim,
      elapsedMs: reply.elapsedMs,
    );
  }

  /// 本地提取：不联网
  static Future<LocalExtractResult> extract(Uint8List bytes) async {
    final ImageData source = await decodeImage(bytes);
    final int seed = await ensureSeed();
    final _ExtractPayload payload = _ExtractPayload(
      rgba: source.rgba,
      width: source.width,
      height: source.height,
      seed: seed,
    );
    final _ExtractReply reply = await Isolate.run(() => _extractInIsolate(payload));
    return LocalExtractResult(
      found: reply.found,
      trace: reply.trace == null ? null : TraceCode.fromBytes(reply.trace!),
      confidence: reply.confidence,
      corrected: reply.corrected,
      reason: reply.reason,
      elapsedMs: reply.elapsedMs,
    );
  }
}

class _EmbedPayload {
  const _EmbedPayload({
    required this.rgba,
    required this.width,
    required this.height,
    required this.traceBytes,
    required this.seed,
  });
  final Uint8List rgba;
  final int width;
  final int height;
  final List<int> traceBytes;
  final int seed;
}

class _EmbedReply {
  const _EmbedReply({
    required this.rgba,
    required this.width,
    required this.height,
    required this.psnr,
    required this.ssim,
    required this.elapsedMs,
  });
  final Uint8List rgba;
  final int width;
  final int height;
  final double psnr;
  final double ssim;
  final double elapsedMs;
}

_EmbedReply _embedInIsolate(_EmbedPayload p) {
  final Stopwatch watch = Stopwatch()..start();
  final ImageData image = ImageData(width: p.width, height: p.height, rgba: p.rgba);
  final TraceCode trace = TraceCode.fromBytes(p.traceBytes);
  final EmbedOutcome outcome = WatermarkEngine.embed(image, trace, p.seed);
  return _EmbedReply(
    rgba: outcome.image.rgba,
    width: outcome.image.width,
    height: outcome.image.height,
    psnr: outcome.psnr,
    ssim: outcome.ssim,
    elapsedMs: watch.elapsedMicroseconds / 1000.0,
  );
}

class _ExtractPayload {
  const _ExtractPayload({
    required this.rgba,
    required this.width,
    required this.height,
    required this.seed,
  });
  final Uint8List rgba;
  final int width;
  final int height;
  final int seed;
}

class _ExtractReply {
  const _ExtractReply({
    required this.found,
    this.trace,
    this.confidence = 0,
    this.corrected = 0,
    this.reason = '',
    required this.elapsedMs,
  });
  final bool found;
  final List<int>? trace;
  final double confidence;
  final int corrected;
  final String reason;
  final double elapsedMs;
}

_ExtractReply _extractInIsolate(_ExtractPayload p) {
  final Stopwatch watch = Stopwatch()..start();
  final ImageData image = ImageData(width: p.width, height: p.height, rgba: p.rgba);
  final ExtractOutcome outcome = WatermarkEngine.extract(image, p.seed);
  return _ExtractReply(
    found: outcome.found,
    trace: outcome.trace?.toBytes(),
    confidence: outcome.confidence,
    corrected: outcome.corrected,
    reason: outcome.reason,
    elapsedMs: watch.elapsedMicroseconds / 1000.0,
  );
}
