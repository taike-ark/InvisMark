// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 极简全局状态：ChangeNotifier + InheritedNotifier，不引入 provider / riverpod。
// 持久化：仅进程内有效；M3 决定用 shared_preferences 还是 profile 目录文件后再补。

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/trace_codec.dart';
import '../models/trace.dart';
import '../services/api_client.dart';
import '../services/local_engine.dart';
import '../services/native_media.dart';
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

  /// Android 模拟器访问宿主机用 10.0.2.2；真机在设置页改成局域网 IP。
  /// 构建时可用 `--dart-define=INVISMARK_API=http://192.168.1.10:8000` 覆盖默认值。
  static const String defaultBaseUrl = String.fromEnvironment(
    'INVISMARK_API',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// 首页最多保留的最近任务条数
  static const int maxRecentTasks = 3;

  String apiBaseUrl;
  String? authToken;

  /// 本地离线模式（默认开）：嵌入/提取都在手机本机完成，不需要服务端。
  bool offlineMode = true;

  ThemePreference themePreference = ThemePreference.system;
  GlassPreference glassPreference = GlassPreference.auto;

  bool embedding = false;
  DetectStatus detectStatus = DetectStatus.idle;
  EmbedResult? lastEmbed;
  TraceResult? lastTrace;
  String? errorMessage;

  /// 本月用量（GET /v1/quota），未连上服务端时保持 0
  int quotaUsed = 0;
  int quotaLimit = 1000;

  /// 最近一次真实嵌入的成图字节（结果页展示 / 保存相册 / 分享）
  Uint8List? lastWatermarkedBytes;
  String? lastWatermarkedName;

  /// 最近一次选中的原始图片（重试、再次嵌入可用）
  PickedImage? lastPicked;

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

  /// 启动时读取本地设置（API 地址 / 主题 / 玻璃档位），并拉一次配额。
  Future<void> init() async {
    final Map<String, String> prefs = await NativeMedia.loadPrefs();
    final String? baseUrl = prefs['baseUrl'];
    if (baseUrl != null) {
      final String? normalized = normalizeBaseUrl(baseUrl);
      if (normalized != null && normalized != apiBaseUrl) {
        apiBaseUrl = normalized;
        _client?.dispose();
        _client = null;
      }
    }
    final String? token = prefs['authToken'];
    if (token != null && token.isNotEmpty) {
      authToken = token;
    }
    final String? theme = prefs['theme'];
    themePreference = ThemePreference.values.firstWhere(
      (ThemePreference value) => value.name == theme,
      orElse: () => ThemePreference.system,
    );
    final String? glass = prefs['glass'];
    glassPreference = GlassPreference.values.firstWhere(
      (GlassPreference value) => value.name == glass,
      orElse: () => GlassPreference.auto,
    );
    offlineMode = prefs['offline'] != 'false'; // 默认本地离线
    notifyListeners();
    // 本地模式不需要服务端；服务端模式才拉配额
    if (!offlineMode) {
      await refreshQuota(quiet: true);
    }
  }

  void setOfflineMode(bool value) {
    if (offlineMode == value) {
      return;
    }
    offlineMode = value;
    NativeMedia.savePref('offline', value ? 'true' : 'false');
    notifyListeners();
    if (!value) {
      refreshQuota(quiet: true);
    }
  }

  /// 拉取本月用量；[quiet] 为 true 时不把错误写进界面。
  Future<bool> refreshQuota({bool quiet = false}) async {
    try {
      final Map<String, dynamic> json = await client.quota();
      final int used = (json['used'] as num?)?.toInt() ?? quotaUsed;
      final int limit = (json['limit'] as num?)?.toInt() ?? quotaLimit;
      quotaUsed = used;
      quotaLimit = limit > 0 ? limit : quotaLimit;
      notifyListeners();
      return true;
    } catch (error) {
      if (!quiet) {
        errorMessage = '无法获取配额：$error';
        notifyListeners();
      }
      return false;
    }
  }

  /// 设置页「测试连接」：成功返回 null，失败返回错误文案。
  Future<String?> testConnection() async {
    try {
      final Map<String, dynamic> json = await client.health();
      if (json['ok'] == true) {
        await refreshQuota(quiet: true);
        return null;
      }
      return '服务返回异常：$json';
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return '连接失败：$error';
    }
  }

  void setThemePreference(ThemePreference value) {
    if (themePreference == value) {
      return;
    }
    themePreference = value;
    NativeMedia.savePref('theme', value.name);
    notifyListeners();
  }

  void setGlassPreference(GlassPreference value) {
    if (glassPreference == value) {
      return;
    }
    glassPreference = value;
    NativeMedia.savePref('glass', value.name);
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
    NativeMedia.savePref('baseUrl', normalized);
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

  /// 嵌入单图：离线模式走本地引擎，否则走服务端。返回是否成功。
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
    lastPicked = PickedImage(bytes: bytes, name: filename);
    notifyListeners();

    try {
      if (offlineMode) {
        final LocalEmbedResult local = await LocalEngine.embed(bytes, resourceCode: resourceCode);
        final EmbedResult result = EmbedResult(
          assetId: 'local',
          traceId: local.traceId,
          quality: EmbedQuality(psnr: local.psnr, ssim: local.ssim),
          embeddedAt: DateTime.now().toUtc(),
          imageBytes: local.pngBytes,
        );
        lastEmbed = result;
        lastWatermarkedBytes = result.imageBytes;
        lastWatermarkedName = '${result.traceId}.png';
        recentTasks.insert(0, RecentTask.fromEmbed(result));
        if (recentTasks.length > maxRecentTasks) {
          recentTasks.removeLast();
        }
        embedding = false;
        notifyListeners();
        return true;
      }

      final EmbedResult result = await client.embed(
        bytes: bytes,
        filename: filename,
        resourceCode: resourceCode,
        strength: strength,
      );
      lastEmbed = result;
      lastWatermarkedBytes = result.imageBytes;
      lastWatermarkedName = '${result.traceId}.png';
      embedding = false;
      recentTasks.insert(0, RecentTask.fromEmbed(result));
      if (recentTasks.length > maxRecentTasks) {
        recentTasks.removeLast();
      }
      notifyListeners();
      refreshQuota(quiet: true);
      return true;
    } on ApiException catch (error) {
      embedding = false;
      errorMessage = error.message;
      notifyListeners();
      return false;
    } on StateError catch (error) {
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

  /// 检测单图：离线模式走本地引擎，否则走服务端。
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
      if (offlineMode) {
        final LocalExtractResult local = await LocalEngine.extract(bytes);
        if (local.found && local.trace != null) {
          final TraceCode trace = local.trace!;
          lastTrace = TraceResult(
            found: true,
            traceId: trace.hex,
            resourceCode: trace.resourceCode,
            embeddedAt: trace.embeddedAt,
            confidence: local.confidence,
            message: '本地引擎检出（用户索引 ${trace.userIndex}）',
          );
          detectStatus = DetectStatus.found;
        } else {
          lastTrace = TraceResult.notFound(
            message: local.reason.isEmpty ? '未在该图片中检出有效追溯码' : local.reason,
          );
          detectStatus = DetectStatus.notFound;
        }
        notifyListeners();
        return local.found;
      }

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
    } on StateError catch (error) {
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

  /// 界面层错误（如选图失败），会显示在首页/检测页的错误条上，不只是一闪而过的 toast。
  void reportError(String message) {
    errorMessage = message;
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
