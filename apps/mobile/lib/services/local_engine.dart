// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 本地离线引擎：手机端独立运行时的嵌入/提取入口。
// 图片解码：PNG 走自研纯 Dart 解码器；其它格式（JPEG/WebP）走 Flutter 引擎解码。
// 计算放到独立 isolate，避免大图处理时卡 UI。

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

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

  /// 解码任意图片为 RGBA，并把长边限制在 [maxInputLongEdge] 内。
  /// 这一步很关键：手机相册常见 4000×3000，全尺寸 RGBA 就要 48MB，
  /// 再叠加水印管线的浮点缓冲会直接 OOM。先降采样能把内存压到 1/4 以下。
  static const int maxInputLongEdge = 1600;

  static Future<ImageData> decodeImage(Uint8List bytes) async {
    final Stopwatch watch = Stopwatch()..start();
    ImageData image;
    if (PngCodec.isPng(bytes)) {
      image = PngCodec.decode(bytes);
    } else {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int w = descriptor.width;
      final int h = descriptor.height;
      final double scale = math.min(1.0, maxInputLongEdge / math.max(w, h));
      final int tw = math.max(1, (w * scale).round());
      final int th = math.max(1, (h * scale).round());
      final ui.Codec codec = await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('图片解码失败');
      }
      image = ImageData(
        width: frame.image.width,
        height: frame.image.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
    image = _capImage(image, maxInputLongEdge);
    debugPrint('[LocalEngine] decode ${image.width}x${image.height} in ${watch.elapsedMilliseconds}ms');
    return image;
  }

  /// 双线性降采样（仅用于把输入压到上限内）
  static ImageData _capImage(ImageData src, int maxEdge) {
    final int longEdge = math.max(src.width, src.height);
    if (longEdge <= maxEdge) return src;
    final double scale = maxEdge / longEdge;
    final int dw = math.max(1, (src.width * scale).round());
    final int dh = math.max(1, (src.height * scale).round());
    final Uint8List out = Uint8List(dw * dh * 4);
    final double sx = src.width / dw;
    final double sy = src.height / dh;
    for (int y = 0; y < dh; y++) {
      final double fy = (y + 0.5) * sy - 0.5;
      int y0 = fy.floor();
      final double wy = fy - y0;
      if (y0 < 0) y0 = 0;
      final int y1 = math.min(y0 + 1, src.height - 1);
      for (int x = 0; x < dw; x++) {
        final double fx = (x + 0.5) * sx - 0.5;
        int x0 = fx.floor();
        final double wx = fx - x0;
        if (x0 < 0) x0 = 0;
        final int x1 = math.min(x0 + 1, src.width - 1);
        final int i00 = (y0 * src.width + x0) * 4;
        final int i01 = (y0 * src.width + x1) * 4;
        final int i10 = (y1 * src.width + x0) * 4;
        final int i11 = (y1 * src.width + x1) * 4;
        final int o = (y * dw + x) * 4;
        for (int c = 0; c < 3; c++) {
          final double top = src.rgba[i00 + c] * (1 - wx) + src.rgba[i01 + c] * wx;
          final double bottom = src.rgba[i10 + c] * (1 - wx) + src.rgba[i11 + c] * wx;
          out[o + c] = (top * (1 - wy) + bottom * wy).round().clamp(0, 255);
        }
        out[o + 3] = 255;
      }
    }
    return ImageData(width: dw, height: dh, rgba: out);
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

  /// 本地引擎自检：不依赖相册权限、不联网，10 秒内验证「嵌入→提取」闭环。
  /// 返回可直接展示给用户的结论；设置页的「本地引擎自检」按钮用它。
  static Future<String> selfTest() async {
    final Stopwatch watch = Stopwatch()..start();
    final int w = 800;
    final int h = 600;
    final Uint8List rgba = Uint8List(w * h * 4);
    final math.Random rng = math.Random(42);
    int p = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final double base = 80 + 120 * (x / w) + 30 * (y / h);
        rgba[p++] = (base + rng.nextDouble() * 24).round().clamp(0, 255);
        rgba[p++] = (base * 0.85 + 20).round().clamp(0, 255);
        rgba[p++] = (base * 0.7 + 40).round().clamp(0, 255);
        rgba[p++] = 255;
      }
    }
    final ImageData image = ImageData(width: w, height: h, rgba: rgba);
    final TraceCode code = TraceCode.newCode(resourceCode: 'SELFT', userIndex: 1);
    final EmbedOutcome embed = WatermarkEngine.embed(image, code, 20261116);
    final Uint8List png = PngCodec.encode(embed.image);
    final ExtractOutcome extract = WatermarkEngine.extract(
      PngCodec.decode(png),
      20261116,
    );
    final bool ok = extract.found && extract.trace?.hex == code.hex;
    return '结果：${ok ? '通过' : '失败'}\n'
        'PSNR：${embed.psnr.toStringAsFixed(1)} dB ｜ SSIM：${embed.ssim.toStringAsFixed(3)}\n'
        '每比特块数：${embed.blocksPerBit} ｜ PNG：${(png.length / 1024).toStringAsFixed(0)} KB\n'
        '提取：${extract.found ? '命中 ${extract.trace?.resourceCode ?? ''}' : '未命中（${extract.reason}）'}\n'
        '耗时：${watch.elapsedMilliseconds} ms';
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
