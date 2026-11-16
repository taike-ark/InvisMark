// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 数据模型：POST /v1/embed 与 POST /v1/extract 的返回体，
// 字段与《项目说明书》§8.1 / §8.2 对齐。手写 fromJson，缺字段时给安全默认值。

import 'dart:convert';
import 'dart:typed_data';

/// 图像质量指标（服务端返回，客户端不重算）。
class EmbedQuality {
  const EmbedQuality({required this.psnr, required this.ssim});

  /// PSNR（dB），基线 ≥ 40
  final double psnr;

  /// SSIM，基线 ≥ 0.98
  final double ssim;

  factory EmbedQuality.fromJson(Map<String, dynamic>? json) => EmbedQuality(
        psnr: _asDouble(json?['psnr']),
        ssim: _asDouble(json?['ssim']),
      );

  factory EmbedQuality.demo() => const EmbedQuality(psnr: 42.7, ssim: 0.991);

  /// 「PSNR 42.7 dB」这样的展示串
  String get psnrLabel => 'PSNR ${psnr.toStringAsFixed(1)} dB';

  /// SSIM 保留三位小数
  String get ssimLabel => 'SSIM ${ssim.toStringAsFixed(3)}';

  /// 是否达到说明书 §2 的画质基线
  bool get meetsBaseline => psnr >= 40 && ssim >= 0.98;
}

/// 嵌入结果（§8.1）。
class EmbedResult {
  const EmbedResult({
    required this.assetId,
    required this.traceId,
    required this.quality,
    this.imageUrl,
    this.embeddedAt,
    this.expiresAt,
    this.imageBytes,
    this.customText,
  });

  final String assetId;
  final String traceId;
  final EmbedQuality quality;
  final String? imageUrl;
  final DateTime? embeddedAt;
  final DateTime? expiresAt;

  /// 服务端返回的成图（PNG 字节），用于结果页展示、保存到相册、分享
  final Uint8List? imageBytes;

  /// v2 自定义嵌入内容（用户自填文本）
  final String? customText;

  factory EmbedResult.fromJson(Map<String, dynamic> json) => EmbedResult(
        assetId: _asString(json['asset_id']) ?? '',
        traceId: _asString(json['trace_id']) ?? '',
        imageUrl: _asString(json['image_url']),
        quality: EmbedQuality.fromJson(_asMap(json['quality'])),
        embeddedAt: _asDateTime(json['embedded_at']),
        expiresAt: _asDateTime(json['expires_at']),
        imageBytes: _decodeBase64(json['image_base64']),
        customText: _asString(json['custom_text']),
      );

  /// 演示数据：未接入原生相册插件 / 无网络时用于走通 UI 流程。
  factory EmbedResult.demo() => EmbedResult(
        assetId: 'as_demo_8f2c',
        traceId: 'F1B2C3D4E5F60718293A4B5C',
        quality: EmbedQuality.demo(),
        embeddedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 90)),
      );

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}

/// 提取结果里的归属用户（§8.2）。
class TraceUser {
  const TraceUser({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  factory TraceUser.fromJson(Map<String, dynamic> json) => TraceUser(
        userId: _asString(json['user_id']) ?? '',
        displayName: _asString(json['display_name']) ?? '未知用户',
      );
}

/// 提取 / 溯源结果（§8.2）。未命中也是合法结果，不是异常。
class TraceResult {
  const TraceResult({
    required this.found,
    this.traceId,
    this.tenantId,
    this.user,
    this.resourceCode,
    this.customText,
    this.embeddedAt,
    this.confidence,
    this.reportUrl,
    this.message,
  });

  final bool found;
  final String? traceId;
  final String? tenantId;
  final TraceUser? user;
  final String? resourceCode;

  /// v2 自定义嵌入内容（用户自填文本）
  final String? customText;

  final DateTime? embeddedAt;

  /// 置信度 0..1，≥ 0.9 展示"高置信"（§4.5）
  final double? confidence;

  /// 证据包（PDF）链接
  final String? reportUrl;

  /// 未命中时的补充说明
  final String? message;

  factory TraceResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? userJson = _asMap(json['user']);
    return TraceResult(
      found: json['found'] == true,
      traceId: _asString(json['trace_id']),
      tenantId: _asString(json['tenant_id']),
      user: userJson == null ? null : TraceUser.fromJson(userJson),
      resourceCode: _asString(json['resource_code']),
      customText: _asString(json['custom_text']),
      embeddedAt: _asDateTime(json['embedded_at']),
      confidence: json['confidence'] == null ? null : _asDouble(json['confidence']),
      reportUrl: _asString(json['report_url']),
      message: _asString(json['message']),
    );
  }

  factory TraceResult.notFound({String? message}) =>
      TraceResult(found: false, message: message);

  /// 演示数据：命中
  factory TraceResult.demoFound() => TraceResult(
        found: true,
        traceId: 'F1B2C3D4E5F60718293A4B5C',
        tenantId: 't_demo',
        user: const TraceUser(userId: 'u_10293', displayName: '张*'),
        resourceCode: 'F13241',
        embeddedAt: DateTime.now().subtract(const Duration(hours: 3)),
        confidence: 0.94,
        reportUrl: 'https://example.com/rpt_demo.pdf',
      );

  /// 置信度档位文案；色觉障碍用户也能靠文字区分（§8）
  String get confidenceLabel {
    final double? value = confidence;
    if (value == null) {
      return '置信度未知';
    }
    if (value >= 0.9) {
      return '高置信';
    }
    if (value >= 0.7) {
      return '中置信';
    }
    return '低置信';
  }

  /// 置信度百分比展示，如「94%」
  String get confidencePercentLabel {
    final double? value = confidence;
    if (value == null) {
      return '—';
    }
    return '${(value * 100).round()}%';
  }
}

// ─────────────────────────────────────────────────────────────
// JSON 取值兜底（服务端字段可能缺失或类型漂移）
// ─────────────────────────────────────────────────────────────
double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

String? _asString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

DateTime? _asDateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  return null;
}

Uint8List? _decodeBase64(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

/// 时间展示：2026-11-15 17:20（本地时区）。不引 intl，手动补零。
String formatTimestamp(DateTime? time) {
  if (time == null) {
    return '—';
  }
  final DateTime local = time.toLocal();
  return '${local.year}-${_pad2(local.month)}-${_pad2(local.day)} '
      '${_pad2(local.hour)}:${_pad2(local.minute)}';
}

String _pad2(int value) => value.toString().padLeft(2, '0');
