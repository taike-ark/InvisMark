// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 原生媒体桥（零第三方插件）：Android 侧由 MainActivity 的 MethodChannel 实现，
// 提供相册选图 / 相机拍照 / 保存到相册 / 系统分享 / 设置持久化。
// iOS 侧暂未实现（通道缺失时抛 UnsupportedError，由界面提示「当前平台不支持」）。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
/// 选中的图片：原始字节 + 文件名（文件名用于推断 MIME 与落盘名）。
class PickedImage {
  const PickedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  int get sizeInBytes => bytes.length;
}

class NativeMediaException implements Exception {
  const NativeMediaException(this.message, {this.code});

  final String message;
  final String? code;

  bool get cancelled => code == 'cancelled';

  @override
  String toString() => message;
}

class NativeMedia {
  NativeMedia._();

  static const MethodChannel _channel = MethodChannel('invismark/media');

  /// 相册选图：先拉起系统相册，再轮询原生侧落盘的结果。
  /// 这样即使 Activity/FlutterEngine 被 ROM 重建，也不会丢图或闪退。
  static Future<PickedImage> pickImage() => _startAndAwait('pickImage');

  /// 相机拍照
  static Future<PickedImage> capturePhoto() => _startAndAwait('capturePhoto');

  static const Duration _pollInterval = Duration(milliseconds: 400);
  static const Duration _pollTimeout = Duration(minutes: 3);

  static Future<PickedImage> _startAndAwait(String method) async {
    try {
      final Object? started = await _channel.invokeMethod<Object?>(method);
      if (started == null) {
        throw const NativeMediaException('无法打开相册/相机');
      }
    } on PlatformException catch (error) {
      debugPrint('[NativeMedia] $method PlatformException ${error.code} ${error.message}');
      throw NativeMediaException(error.message ?? '操作失败', code: error.code);
    } on MissingPluginException {
      throw const NativeMediaException('当前平台暂不支持选图（仅 Android 可用）');
    }

    final DateTime deadline = DateTime.now().add(_pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final PickedImage? picked = await consumePendingPick();
      if (picked != null) {
        return picked;
      }
      await Future<void>.delayed(_pollInterval);
    }
    throw const NativeMediaException('等待图片超时，请重试', code: 'timeout');
  }

  /// 取走上一次选图结果（原生侧落盘文件），没有则返回 null。
  static Future<PickedImage?> consumePendingPick() async {
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('consumePendingPick');
      if (raw == null) {
        return null;
      }
      final Object? bytes = raw['bytes'];
      if (bytes is! Uint8List || bytes.isEmpty) {
        return null;
      }
      final String name =
          (raw['name'] as String?)?.trim().isNotEmpty == true
              ? raw!['name'] as String
              : 'image.png';
      debugPrint('[NativeMedia] consumed ${bytes.length} bytes ($name)');
      return PickedImage(bytes: bytes, name: name);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 保存到系统相册，返回相册内路径
  static Future<String> saveToGallery(Uint8List bytes, String name) async {
    try {
      final String? path = await _channel.invokeMethod<String>(
        'saveToGallery',
        <String, Object>{'bytes': bytes, 'name': name},
      );
      return path ?? '';
    } on PlatformException catch (error) {
      throw NativeMediaException(error.message ?? '保存失败', code: error.code);
    } on MissingPluginException {
      throw const NativeMediaException('当前平台暂不支持保存到相册');
    }
  }

  /// 调起系统分享
  static Future<void> shareBytes(Uint8List bytes, String name) async {
    try {
      await _channel.invokeMethod<bool>(
        'shareBytes',
        <String, Object>{'bytes': bytes, 'name': name},
      );
    } on PlatformException catch (error) {
      throw NativeMediaException(error.message ?? '分享失败', code: error.code);
    } on MissingPluginException {
      throw const NativeMediaException('当前平台暂不支持分享');
    }
  }

  /// 读取本地设置（baseUrl / theme / glass 等）
  static Future<Map<String, String>> loadPrefs() async {
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('getPrefs');
      return raw?.map((Object? k, Object? v) =>
              MapEntry<String, String>('$k', '$v')) ??
          <String, String>{};
    } on MissingPluginException {
      return <String, String>{};
    } on PlatformException {
      return <String, String>{};
    }
  }

  static Future<void> savePref(String key, String value) async {
    try {
      await _channel.invokeMethod<bool>(
        'setPref',
        <String, Object>{'key': key, 'value': value},
      );
    } on MissingPluginException {
      // 桌面/测试环境无原生桥，忽略即可
    } on PlatformException {
      // 写失败不阻塞主流程
    }
  }
}
