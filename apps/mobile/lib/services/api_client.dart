// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 后端客户端：零第三方依赖，只用 dart:io + dart:convert。
// 接口：POST /v1/embed、POST /v1/extract（multipart 自己拼，字段见《项目说明书》§8）。
// 超时：连接 10s、单次请求 60s；失败按指数退避重试（默认 2 次）。
// 注意：dart:io 不支持 Web，若 M3 要出 Web 版需另写适配层。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/trace.dart';

/// 统一的接口异常：带 HTTP 状态码、可读文案、是否可重试。
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.retryable = false,
  });

  final String message;
  final int? statusCode;
  final bool retryable;

  factory ApiException.network(Object? cause) => ApiException(
        message: '网络请求失败：${cause ?? '原因未知'}',
        retryable: true,
      );

  @override
  String toString() => statusCode == null ? message : '[$statusCode] $message';
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    this.authToken,
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    this.retryBaseDelay = const Duration(milliseconds: 400),
  }) : _baseUri = Uri.parse(_normalizeBaseUrl(baseUrl));

  /// X-Client 头（§8.1）
  static const String clientId = 'mobile/0.1.0';

  final Uri _baseUri;
  final String? authToken;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final int maxRetries;
  final Duration retryBaseDelay;

  late final HttpClient _http = HttpClient()..connectionTimeout = connectTimeout;

  Uri get baseUri => _baseUri;

  /// 单图嵌入：multipart(file, resource_code?, strength?, custom_text?)
  Future<EmbedResult> embed({
    required Uint8List bytes,
    required String filename,
    String? resourceCode,
    String? strength,
    String? customText,
  }) async {
    final Map<String, dynamic> json = await _postMultipart(
      '/v1/embed',
      fields: <String, String?>{
        'resource_code': resourceCode,
        'strength': strength,
        'custom_text': customText,
      },
      bytes: bytes,
      filename: filename,
    );
    return EmbedResult.fromJson(json);
  }

  /// 提取溯源：multipart(file)
  Future<TraceResult> extract({
    required Uint8List bytes,
    required String filename,
  }) async {
    final Map<String, dynamic> json = await _postMultipart(
      '/v1/extract',
      fields: const <String, String?>{},
      bytes: bytes,
      filename: filename,
    );
    return TraceResult.fromJson(json);
  }

  /// 可分享的溯源证据页地址。
  /// 占位实现：M3 与服务端 /v1/reports、GET /v1/traces/{id} 的展示路由对齐。
  String traceUrl(String traceId) => _baseUri.resolve('/r/$traceId').toString();

  /// 健康检查（设置页「测试连接」）
  Future<Map<String, dynamic>> health() async {
    return _getJson('/healthz');
  }

  /// 本月用量与配额（首页进度条）
  Future<Map<String, dynamic>> quota() async {
    return _getJson('/v1/quota');
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final Uri uri = _baseUri.resolve(path);
    try {
      final HttpClientRequest request = await _http.getUrl(uri).timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-Client', clientId);
      final HttpClientResponse response = await request.close().timeout(requestTimeout);
      final String raw = await response.transform(utf8.decoder).join().timeout(requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return <String, dynamic>{};
      }
      throw _errorForStatus(response.statusCode, raw);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException.network(error);
    }
  }

  /// 释放底层连接池。切换 API 地址时必须调用。
  void dispose() => _http.close(force: true);

  // ── multipart 组装 ──────────────────────────────────────
  Future<Map<String, dynamic>> _postMultipart(
    String path, {
    required Map<String, String?> fields,
    required Uint8List bytes,
    required String filename,
  }) async {
    final String boundary = '----invismark-${DateTime.now().microsecondsSinceEpoch}';
    final Uint8List body = _buildMultipartBody(
      boundary: boundary,
      fields: fields,
      fileField: 'file',
      filename: filename,
      fileBytes: bytes,
    );
    return _sendWithRetry(
      path: path,
      body: body,
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  Uint8List _buildMultipartBody({
    required String boundary,
    required Map<String, String?> fields,
    required String fileField,
    required String filename,
    required Uint8List fileBytes,
  }) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    void addText(String text) => builder.add(utf8.encode(text));

    fields.forEach((String key, String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      addText('--$boundary\r\n');
      addText('Content-Disposition: form-data; name="$key"\r\n\r\n');
      addText('$value\r\n');
    });

    addText('--$boundary\r\n');
    addText('Content-Disposition: form-data; name="$fileField"; '
        'filename="${_sanitizeFilename(filename)}"\r\n');
    addText('Content-Type: ${_mimeTypeOf(filename)}\r\n\r\n');
    builder.add(fileBytes);
    addText('\r\n--$boundary--\r\n');

    return builder.takeBytes();
  }

  // ── 发送 + 退避重试 ─────────────────────────────────────
  Future<Map<String, dynamic>> _sendWithRetry({
    required String path,
    required Uint8List body,
    required String contentType,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _sendOnce(path: path, body: body, contentType: contentType);
      } on ApiException catch (error) {
        // 4xx 业务错误（尺寸过小、配额超限等）重试无意义，直接抛出
        if (!error.retryable) {
          rethrow;
        }
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } on HttpException catch (error) {
        lastError = error;
      } on FormatException catch (error) {
        lastError = error;
      }

      if (attempt < maxRetries) {
        // 指数退避：400ms → 800ms
        await Future<void>.delayed(retryBaseDelay * (1 << attempt));
      }
    }
    throw ApiException.network(lastError);
  }

  Future<Map<String, dynamic>> _sendOnce({
    required String path,
    required Uint8List body,
    required String contentType,
  }) async {
    final Uri uri = _baseUri.resolve(path);
    final HttpClientRequest request = await _http.postUrl(uri).timeout(requestTimeout);
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    // 服务端在 Accept 命中 application/json 且不含 image 时只回 JSON；
    // 这里用 */* 让它把成图 base64 一起带回来（结果页/相册保存都需要）。
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    request.headers.set('X-Client', clientId);

    final String? token = authToken;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    request.add(body);

    final HttpClientResponse response = await request.close().timeout(requestTimeout);
    final String raw = await response.transform(utf8.decoder).join().timeout(requestTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (raw.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: '响应格式异常：不是 JSON 对象',
      );
    }

    throw _errorForStatus(response.statusCode, raw);
  }

  ApiException _errorForStatus(int statusCode, String raw) {
    final String fallback = switch (statusCode) {
      400 => '图片不可解码',
      401 || 403 => '鉴权失败，请重新绑定设备',
      413 => '图片体积超出限制',
      422 => '图片尺寸过小（长边需 ≥ 800px）',
      429 => '配额已用尽，请稍后再试',
      451 => '内容合规拦截',
      >= 500 => '服务端暂时不可用',
      _ => '请求失败（HTTP $statusCode）',
    };
    return ApiException(
      statusCode: statusCode,
      message: _extractMessage(raw) ?? fallback,
      // 5xx 与 429 值得退避重试；embed 在服务端对同图幂等（F-05），重复提交安全
      retryable: statusCode >= 500 || statusCode == 429,
    );
  }

  /// 从错误响应里捞出可读文案；非 JSON 错误页则返回 null。
  String? _extractMessage(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        for (final String key in const <String>['message', 'detail', 'error']) {
          final Object? value = decoded[key];
          if (value is String && value.isNotEmpty) {
            return value;
          }
        }
      }
    } on FormatException {
      // 非 JSON（如网关 HTML 错误页）：交给状态码兜底文案
    }
    return null;
  }
}

String _normalizeBaseUrl(String baseUrl) {
  String value = baseUrl.trim();
  if (value.isEmpty) {
    throw ArgumentError('API 地址不能为空');
  }
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'http://$value';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// 依据扩展名给出 Content-Type；服务端只接受 JPEG/PNG（M3 增加 WebP）。
String _mimeTypeOf(String filename) {
  final String lower = filename.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    return 'image/heic';
  }
  return 'image/jpeg';
}

/// 去掉会破坏 multipart 头部的字符
String _sanitizeFilename(String filename) => filename.replaceAll(RegExp(r'[\r\n"\\]'), '_');

