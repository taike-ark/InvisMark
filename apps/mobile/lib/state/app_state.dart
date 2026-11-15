// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 极简全局状态：ChangeNotifier + InheritedNotifier，不引入 provider / riverpod。
// 持久化：仅进程内有效；M3 决定用 shared_preferences 还是 profile 目录文件后再补。

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/trace.dart';
import '../services/api_client.dart';
import '../theme/tokens.dart';

/// 外观模式（设置页「跟随系统 / 亮 / 暗」）
enum ThemePreference { system, light, dark }

/// 检测页状态机
enum DetectStatus { idle, busy, found, notFound, failed }

/// 首页"最近任务"行：只保留展示需要的字段（缩略图不参与模糊，§4.6）
class RecentTask {
  const RecentTask({
    required this.traceId,
    required this.quality,
    this.imageUrl,
    this.embeddedAt,
  });

  final String traceId;
  final EmbedQuality quality;
  final String? imageUrl;
  final DateTime? embeddedAt;

  factory RecentTask.fromEmbed(EmbedResult result) => RecentTask(
        traceId: result.traceId,
        quality: result.quality,
        imageUrl: result.imageUrl,
        embeddedAt: result.embeddedAt,
      );
}

class AppState extends ChangeNotifier {
  AppState({this.apiBaseUrl = defaultBaseUrl, this.authToken});

  /// Android 模拟器访问宿主机用 10.0.2.2；真机改成局域网 IP（设置页可改）
  static const String defaultBaseUrl = 'http://10.0.2.2:8000';

  /// 首页最多保留的最近任务条数
  static const int maxRecentTasks = 3;

  String apiBaseUrl;
  String? authToken;

  ThemePreference themePreference = ThemePreference.system;
  GlassPreference glassPreference = GlassPreference.auto;

  bool embedding = false;
  DetectStatus detectStatus = DetectStatus.idle;
  EmbedResult? lastEmbed;
  TraceResult? lastTrace;
  String? errorMessage;

  final List<RecentTask> recentTasks = <RecentTask>[];

  ApiClient? _client;

  /// 懒建客户端；地址变更时销毁重建（连接池与地址绑定）
  ApiClient get client =>
      _client ??= ApiClient(baseUrl: apiBaseUrl, authToken: authToken);

  ThemeMode get themeMode => switch (themePreference) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      };

  String get themePreferenceLabel => switch (themePreference) {
        ThemePreference.system => '跟随系统',
        ThemePreference.light => '浅色',
        ThemePreference.dark => '深色',
      };

  String get glassPreferenceLabel => switch (glassPreference) {
        GlassPreference.auto => '自动',
        GlassPreference.full => '完整',
        GlassPreference.lite => '精简',
        GlassPreference.opaque => '关闭',
      };

  bool get hasRecentTasks => recentTasks.isNotEmpty;

  /// 由偏好 + 系统无障碍 + 性能采样解析出实际档位。
  /// reduceTransparency 用 MediaQuery.highContrast 近似（Flutter 无 reduceTransparency 通道）。
  GlassTier resolveTier({
    bool reduceTransparency = false,
    bool powerSaver = false,
    DeviceGrade grade = DeviceGrade.unknown,
    double? measuredFps,
  }) =>
      chooseGlassTier(
        preference: glassPreference,
        reduceTransparency: reduceTransparency,
        powerSaver: powerSaver,
        grade: grade,
        measuredFps: measuredFps,
      );

  void setThemePreference(ThemePreference value) {
    if (themePreference == value) {
      return;
    }
    themePreference = value;
    notifyListeners();
  }

  void setGlassPreference(GlassPreference value) {
    if (glassPreference == value) {
      return;
    }
    glassPreference = value;
    notifyListeners();
  }

  /// 地址合法化：缺 scheme 自动补 http://，非法（无法解析 / 无 host）返回 null。
  static String? normalizeBaseUrl(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final String withScheme =
        value.startsWith('http://') || value.startsWith('https://') ? value : 'http://$value';
    final Uri? uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return withScheme.endsWith('/')
        ? withScheme.substring(0, withScheme.length - 1)
        : withScheme;
  }

  /// 设置页保存入口：校验后写入，非法地址写进 [errorMessage] 并返回 false。
  bool applyBaseUrl(String raw) {
    final String? normalized = normalizeBaseUrl(raw);
    if (normalized == null) {
      errorMessage = 'API 地址不合法，示例：http://192.168.1.10:8000';
      notifyListeners();
      return false;
    }
    if (normalized == apiBaseUrl) {
      return true;
    }
    apiBaseUrl = normalized;
    _client?.dispose();
    _client = null;
    errorMessage = null;
    notifyListeners();
    return true;
  }

  void setAuthToken(String? value) {
    final String? normalized = (value == null || value.trim().isEmpty) ? null : value.trim();
    if (normalized == authToken) {
      return;
    }
    authToken = normalized;
    _client?.dispose();
    _client = null;
    notifyListeners();
  }

  /// 嵌入单图。返回是否成功；失败原因写进 [errorMessage]。
  /// 原生相册/相机插件尚未接入（M3），调用方需要自己提供 bytes。
  Future<bool> embedImage({
    required Uint8List bytes,
    required String filename,
    String? resourceCode,
    String? strength,
  }) async {
    if (embedding) {
      return false;
    }
    embedding = true;
    errorMessage = null;
    notifyListeners();

    try {
      final EmbedResult result = await client.embed(
        bytes: bytes,
        filename: filename,
        resourceCode: resourceCode,
        strength: strength,
      );
      lastEmbed = result;
      embedding = false;
      recentTasks.insert(0, RecentTask.fromEmbed(result));
      if (recentTasks.length > maxRecentTasks) {
        recentTasks.removeLast();
      }
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      embedding = false;
      errorMessage = error.message;
      notifyListeners();
      return false;
    } on Exception catch (error) {
      embedding = false;
      errorMessage = '嵌入失败：$error';
      notifyListeners();
      return false;
    }
  }

  /// 检测单图。未命中是正常结果（detectStatus = notFound），不是错误。
  Future<bool> detectImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (detectStatus == DetectStatus.busy) {
      return false;
    }
    detectStatus = DetectStatus.busy;
    errorMessage = null;
    lastTrace = null;
    notifyListeners();

    try {
      final TraceResult result = await client.extract(bytes: bytes, filename: filename);
      lastTrace = result;
      detectStatus = result.found ? DetectStatus.found : DetectStatus.notFound;
      notifyListeners();
      return result.found;
    } on ApiException catch (error) {
      detectStatus = DetectStatus.failed;
      errorMessage = error.message;
      notifyListeners();
      return false;
    } on Exception catch (error) {
      detectStatus = DetectStatus.failed;
      errorMessage = '检测失败：$error';
      notifyListeners();
      return false;
    }
  }

  /// 演示：无原生插件 / 无后端时走通 UI（结果页、命中卡）。
  void loadDemoEmbed() {
    final EmbedResult result = EmbedResult.demo();
    lastEmbed = result;
    errorMessage = null;
    recentTasks.insert(0, RecentTask.fromEmbed(result));
    if (recentTasks.length > maxRecentTasks) {
      recentTasks.removeLast();
    }
    notifyListeners();
  }

  /// 演示：命中 / 未命中两态
  void loadDemoTrace({bool found = true}) {
    lastTrace = found
        ? TraceResult.demoFound()
        : TraceResult.notFound(message: '未在该图片中检出有效追溯码');
    detectStatus = found ? DetectStatus.found : DetectStatus.notFound;
    errorMessage = null;
    notifyListeners();
  }

  void resetDetect() {
    if (detectStatus == DetectStatus.idle && lastTrace == null) {
      return;
    }
    detectStatus = DetectStatus.idle;
    lastTrace = null;
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) {
      return;
    }
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    _client = null;
    super.dispose();
  }
}

/// 把 [AppState] 提供给子树：`AppStateScope.of(context)` 订阅重建，
/// `AppStateScope.read(context)` 只取值（用于回调，不触发重建）。
class AppStateScope extends InheritedNotifier<AppState> {
  // 注意：这里不能用 super.child 简写，因为同时需要显式调用 super(notifier:)
  const AppStateScope({
    Key? key,
    required AppState state,
    required Widget child,
  }) : super(key: key, notifier: state, child: child);

  static AppState of(BuildContext context) {
    final AppStateScope? scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope 未挂载：请在 MaterialApp 之上包一层');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final AppStateScope? scope = context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope 未挂载：请在 MaterialApp 之上包一层');
    return scope!.notifier!;
  }
}
