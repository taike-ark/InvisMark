// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 设计 Token（唯一来源）。数值出处：
//   docs/wmforge-移动端UI规范-液态玻璃.md §3（Token）、§5（组件规格）、§7（性能降级）、§12（玻璃配方）
//   design/mobile-glass-mockup.html（品牌色 / 背景渐变）
// 约定：页面与组件里不得出现魔法数字或字面色值，一律引用本文件。

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// 品牌语义色（规范 §1.3）
// ─────────────────────────────────────────────────────────────
abstract final class AppBrand {
  /// 主操作：青绿渐变 #34D399 → #22D3EE
  static const Color ctaStart = Color(0xFF34D399);
  static const Color ctaEnd = Color(0xFF22D3EE);
  static const List<Color> ctaGradient = <Color>[ctaStart, ctaEnd];

  /// CTA 上的文字/图标：深墨绿，保证与青绿底对比度 ≥ 4.5:1
  static const Color onCta = Color(0xFF06231D);

  /// 按压时叠加的白色提亮（CTA 亮度 +8%）
  static const Color ctaPressWash = Color(0x14FFFFFF);

  /// CTA 投影（青绿光晕）
  static const Color ctaShadow = Color(0x4034D399);

  /// 溯源（证据 / 命中）
  static const Color trace = Color(0xFF818CF8);

  /// 溯源色上的文字：深靛，保证与 #818CF8 的对比度
  static const Color onTrace = Color(0xFF0A1020);

  /// 警示（分享渠道风险）
  static const Color warn = Color(0xFFFBBF24);

  /// 危险（删除 / 失败）
  static const Color danger = Color(0xFFFB7185);

  /// 警示条底色（琥珀 18%）
  static const Color warnWash = Color(0x2EFBBF24);

  /// 透明（渐变淡出端用）
  static const Color clear = Color(0x00000000);
}

// ─────────────────────────────────────────────────────────────
// 透明度 Token（十六进制 α，避免运行时浮点抖动）
// 只在需要动态计算 alpha 时使用；静态色值直接写在 AppPalette 里。
// ─────────────────────────────────────────────────────────────
abstract final class AppAlpha {
  /// 按压高光扫过的峰值 α（≈0.18）
  static const int pressSweep = 0x2E;

  /// 着色调（如风险条琥珀）叠加 α（≈0.14）
  static const int tintWash = 0x24;

  /// 禁用态 α（≈0.40）
  static const int disabled = 0x66;
}

// ─────────────────────────────────────────────────────────────
// 圆角（规范 §3.1）
// ─────────────────────────────────────────────────────────────
abstract final class AppRadius {
  /// 小标签、输入框内块
  static const double xs = 10;

  /// 图标底、小按钮
  static const double sm = 14;

  /// 列表行、提示条
  static const double md = 20;

  /// 卡片、玻璃面板
  static const double lg = 28;

  /// 底部抽屉、大面板
  static const double xl = 40;

  /// 胶囊按钮、TabBar
  static const double full = 999;
}

// ─────────────────────────────────────────────────────────────
// 间距（4pt 基数，规范 §3.2）
// ─────────────────────────────────────────────────────────────
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// 页面左右安全边距
  static const double page = xl;

  /// 玻璃面板内边距
  static const double glassInner = xl;

  /// 玻璃之间最小间距（重叠会让边缘高光互相污染）
  static const double glassGap = md;
}

// ─────────────────────────────────────────────────────────────
// 字阶（规范 §3.3）。玻璃上最小可用字号 13pt。
// 字体：MiSans 默认 / Inter 西文 / 系统兜底（字体文件待 M3 以 assets 接入）。
// ─────────────────────────────────────────────────────────────
abstract final class AppType {
  static const List<String> fontFallback = <String>[
    'MiSans',
    'Inter',
    'PingFang SC',
    'Microsoft YaHei',
    'Roboto',
  ];

  /// 首页问候、结果页标题
  static const TextStyle display = TextStyle(
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w700,
    fontFamilyFallback: fontFallback,
  );

  /// 页面标题
  static const TextStyle title1 = TextStyle(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    fontFamilyFallback: fontFallback,
  );

  /// 卡片主标题
  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: fontFallback,
  );

  /// 按钮、列表主文案
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: fontFallback,
  );

  /// 正文（玻璃上最小可用字号）
  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: fontFallback,
  );

  /// 辅助说明、溯源时间
  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: fontFallback,
  );

  /// 角标、TabBar 标签。⚠️ 11pt < 13pt：禁止直接放在玻璃上（§3.3），
  /// 玻璃内请改用 footnote，caption 只用于非玻璃区域。
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    fontFamilyFallback: fontFallback,
  );

  /// 等宽字体（trace_id 等）
  static const List<String> monoFallback = <String>['JetBrains Mono', 'Consolas', 'monospace'];
}

// ─────────────────────────────────────────────────────────────
// 动效（规范 §3.4 / §6）
// Flutter 没有 spring()：用带过冲的 Cubic 近似 spring。
// ─────────────────────────────────────────────────────────────
abstract final class AppMotion {
  /// 按压回弹 240ms spring(0.34, 1.2)
  static const Duration press = Duration(milliseconds: 240);

  /// 抽屉进出 320ms easeOutQuint
  static const Duration sheet = Duration(milliseconds: 320);

  /// 玻璃入场 160ms easeOut
  static const Duration enter = Duration(milliseconds: 160);

  /// Tab 指示器形变 260ms spring(0.3, 1.0)
  static const Duration tab = Duration(milliseconds: 260);

  /// 高光跟随 120ms easeOut
  static const Duration highlight = Duration(milliseconds: 120);

  /// Toast 停留 2.4s
  static const Duration toast = Duration(milliseconds: 2400);

  /// 近似 spring(0.34, 1.2)（y 过冲 1.2 用于按压回弹）
  static const Curve pressCurve = Cubic(0.34, 1.2, 0.64, 1.0);

  /// 近似 spring(0.3, 1.0)
  static const Curve tabCurve = Cubic(0.3, 1.0, 0.55, 1.0);

  static const Curve sheetCurve = Curves.easeOutQuint;
  static const Curve enterCurve = Curves.easeOut;

  /// 按下缩放：主卡 0.97
  static const double pressScale = 0.97;

  /// 按下缩放：胶囊导航 0.98
  static const double pillPressScale = 0.98;

  /// 按下时玻璃白 α 增量
  static const double pressHighlightBoost = 0.06;

  /// Reduce Motion 下的统一时长（§6）
  static const Duration reduceMotion = Duration(milliseconds: 160);
}

// ─────────────────────────────────────────────────────────────
// 尺寸（规范 §5 组件规格、§7.1 预算）
// ─────────────────────────────────────────────────────────────
abstract final class AppLayout {
  /// 所有可点击区域下限（§8）
  static const double minTouchTarget = 44;

  /// 胶囊导航高度：规范 §5 写 H40，但 §8 要求触控目标 ≥ 44，取 44 兜住两者
  static const double navPillHeight = 44;

  /// 悬浮 TabBar 高度
  static const double tabBarHeight = 64;

  /// TabBar 距底部安全区间距
  static const double tabBarBottomInset = 18;

  /// 主按钮高度（实色渐变，不用玻璃）
  static const double primaryButtonHeight = 56;

  /// 次按钮高度
  static const double secondaryButtonHeight = 48;

  /// 进度环直径
  static const double progressRingSize = 72;

  /// 线性进度条最小高度
  static const double progressBarHeight = 6;

  /// 同屏玻璃数量上限（含 TabBar）
  static const int maxGlassPerScreen = 3;

  /// 冷启动首帧强制 Opaque，之后切回真实档位（§7.1）
  static const Duration coldStartOpaqueHold = Duration(milliseconds: 200);

  /// Toast 高度
  static const double toastHeight = 44;

  /// 首页"最近一张图"区域高度
  static const double heroHeight = 168;

  /// 检测页取景区高度
  static const double viewfinderHeight = 220;

  /// 取景准星：内缩与臂长
  static const double viewfinderInset = AppSpacing.xl;
  static const double viewfinderArm = AppSpacing.xxl;
  static const double viewfinderStrokeWidth = 2;

  /// 详情页"标签 : 值"行里标签列的宽度
  static const double keyValueLabelWidth = 84;

  /// 底部抽屉把手尺寸
  static const double sheetHandleWidth = AppSpacing.huge;
  static const double sheetHandleHeight = AppSpacing.xs;

  /// 页面背景品牌光斑直径（玻璃的折射来源，非玻璃材质）
  static const double backdropBlobA = 420;
  static const double backdropBlobB = 380;
  static const double backdropBlobC = 460;

  /// 页面水平内边距
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: AppSpacing.page);

  /// 列表底部留白 = TabBar 高度 + 悬浮间距 + 呼吸
  static const double scrollBottomInset =
      tabBarHeight + tabBarBottomInset + AppSpacing.xxxl;
}

abstract final class AppIconSize {
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 28;
  static const double xl = 34;
}

abstract final class AppShadow {
  /// 玻璃投影 0 12 32 rgba(0,0,0,.12/.40)
  static const Offset glassOffset = Offset(0, 12);
  static const double glassBlur = 32;
  static const double glassSpread = 0;

  /// CTA 光晕
  static const Offset ctaOffset = Offset(0, 8);
  static const double ctaBlur = 24;

  /// 焦点玻璃边缘光的模糊 sigma（青绿描边外发光）
  static const double focusRimBlur = 2;
}

// ─────────────────────────────────────────────────────────────
// 玻璃档位（规范 §7.2）
// ─────────────────────────────────────────────────────────────
enum GlassTier {
  /// 旗舰/近两年中端：blur 24 + 焦点折射 + 实时高光
  full,

  /// 检测到掉帧或设备分级 C：blur 12，关掉 shader 与实时高光
  lite,

  /// 低端机 / 系统「降低透明度」/ 省电模式：完全不用 BackdropFilter
  opaque,
}

/// 用户设置项「视觉效果：自动 / 完整 / 精简 / 关闭」（§7.2 末段）
enum GlassPreference { auto, full, lite, opaque }

/// 设备分级（白/黑名单，M3 由性能采样填充）
enum DeviceGrade { unknown, high, mid, low }

/// 每档玻璃的材质参数（不含颜色，颜色随亮暗取自 AppPalette）
class GlassMaterialSpec {
  const GlassMaterialSpec({
    required this.tier,
    required this.blurSigma,
    required this.usesBackdropFilter,
    required this.animatesHighlight,
    required this.saturation,
  });

  final GlassTier tier;

  /// BackdropFilter 的高斯模糊半径（规范 §7.1：单块 ≤ 24）
  final double blurSigma;

  /// opaque 档为 false：绝不创建 BackdropFilter
  final bool usesBackdropFilter;

  /// lite/opaque 关闭实时高光动画（只有按下 α 变化）
  final bool animatesHighlight;

  /// 饱和提升 180%；Flutter 无内置 saturate 滤镜，需 M3 焦点 shader 实现，
  /// 此处仅作为参数来源，M3 前不影响渲染。
  final double saturation;

  static const GlassMaterialSpec full = GlassMaterialSpec(
    tier: GlassTier.full,
    blurSigma: 24,
    usesBackdropFilter: true,
    animatesHighlight: true,
    saturation: 1.8,
  );

  static const GlassMaterialSpec lite = GlassMaterialSpec(
    tier: GlassTier.lite,
    blurSigma: 12,
    usesBackdropFilter: true,
    animatesHighlight: false,
    saturation: 1.8,
  );

  static const GlassMaterialSpec opaque = GlassMaterialSpec(
    tier: GlassTier.opaque,
    blurSigma: 0,
    usesBackdropFilter: false,
    animatesHighlight: false,
    saturation: 1.0,
  );

  static GlassMaterialSpec of(GlassTier tier) => switch (tier) {
        GlassTier.full => full,
        GlassTier.lite => lite,
        GlassTier.opaque => opaque,
      };
}

/// 档位解析：用户设置 → 系统无障碍/省电 → 性能采样 → 设备分级。
/// 纯函数，方便单测与在设置页预览档位。
GlassTier chooseGlassTier({
  required GlassPreference preference,
  bool reduceTransparency = false,
  bool powerSaver = false,
  DeviceGrade grade = DeviceGrade.unknown,
  double? measuredFps,
}) {
  if (preference == GlassPreference.full) {
    return GlassTier.full;
  }
  if (preference == GlassPreference.lite) {
    return GlassTier.lite;
  }
  if (preference == GlassPreference.opaque) {
    return GlassTier.opaque;
  }
  // auto：无障碍/省电优先，避免"能看见但看不清"（§7.2）
  if (reduceTransparency || powerSaver) {
    return GlassTier.opaque;
  }
  // 设备分级 C 或 200ms 采样平均 < 50fps → Lite
  if (grade == DeviceGrade.low || (measuredFps != null && measuredFps < 50)) {
    return GlassTier.lite;
  }
  return GlassTier.full;
}

// ─────────────────────────────────────────────────────────────
// 亮/暗双模式配色（规范 §3.5 + §12 配方）
// α 值用十六进制常量写死：0.14→0x24、0.06→0x0F、0.55→0x8C、0.30→0x4D、0.40→0x66
// ─────────────────────────────────────────────────────────────
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.backgroundGradient,
    required this.accentA,
    required this.accentB,
    required this.accentC,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.glassTextPrimary,
    required this.glassTextSecondary,
    required this.glassOverlayWhite,
    required this.glassOverlayBlack,
    required this.glassHighlightStrong,
    required this.glassHighlightSoft,
    required this.glassHighlightFade,
    required this.glassPressHighlight,
    required this.glassRimTop,
    required this.glassRimOther,
    required this.glassShadow,
    required this.glassOpaqueSheen,
    required this.opaqueSurfaceGradient,
    required this.focusRim,
    required this.surface,
    required this.border,
    required this.divider,
    required this.chipSelected,
  });

  final Brightness brightness;

  /// 页面底色渐变
  final List<Color> backgroundGradient;

  /// 三处品牌色光斑（仅作玻璃折射来源，本身不是玻璃）
  final Color accentA;
  final Color accentB;
  final Color accentC;

  /// 普通页面文字
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 玻璃上的文字（§2 Z3：主 .92 / 次 .60）
  final Color glassTextPrimary;
  final Color glassTextSecondary;

  /// 玻璃双 overlay（§3.5：亮 → 白 .14 / 黑 .06；暗 → 白 .06 / 黑 .38）
  final Color glassOverlayWhite;
  final Color glassOverlayBlack;

  /// 镜面高光（§2 高光公式：左上 .22、右下 .08）
  final Color glassHighlightStrong;
  final Color glassHighlightSoft;
  final Color glassHighlightFade;

  /// 按压高光扫过的基色
  final Color glassPressHighlight;

  /// 边缘透镜描边（§2 Z2：顶部 .55/其它 .14；暗色 .30/.10）
  final Color glassRimTop;
  final Color glassRimOther;

  /// 投影（§3.5：亮 0.12 / 暗 0.40）
  final Color glassShadow;

  /// opaque 档额外的一层极淡白，避免不透明卡片显得死板
  final Color glassOpaqueSheen;

  /// opaque 档不透明渐变底（保留圆角与层级，视觉不塌）
  final List<Color> opaqueSurfaceGradient;

  /// 焦点玻璃边缘光（每屏 ≤ 1 块）
  final Color focusRim;

  /// 非玻璃小面（输入框内块、未选中 chip）
  final Color surface;
  final Color border;
  final Color divider;
  final Color chipSelected;

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    backgroundGradient: <Color>[Color(0xFFEFF3FA), Color(0xFFE7EEF8), Color(0xFFF7F9FD)],
    accentA: Color(0x3322D3EE),
    accentB: Color(0x33818CF8),
    accentC: Color(0x2E34D399),
    textPrimary: Color(0xFF10131A),
    textSecondary: Color(0x9910131A),
    textTertiary: Color(0x6610131A),
    glassTextPrimary: Color(0xEB10131A),
    glassTextSecondary: Color(0x9910131A),
    glassOverlayWhite: Color(0x24FFFFFF),
    glassOverlayBlack: Color(0x0F000000),
    glassHighlightStrong: Color(0x38FFFFFF),
    glassHighlightSoft: Color(0x14FFFFFF),
    glassHighlightFade: Color(0x00FFFFFF),
    glassPressHighlight: Color(0x2EFFFFFF),
    glassRimTop: Color(0x8CFFFFFF),
    glassRimOther: Color(0x24FFFFFF),
    glassShadow: Color(0x1F000000),
    glassOpaqueSheen: Color(0x0AFFFFFF),
    opaqueSurfaceGradient: <Color>[Color(0xFFF7F9FD), Color(0xFFE8EEF7)],
    focusRim: Color(0x8C22D3EE),
    surface: Color(0xFFFFFFFF),
    border: Color(0x1A10131A),
    divider: Color(0x1410131A),
    chipSelected: Color(0x2634D399),
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    backgroundGradient: <Color>[Color(0xFF070A10), Color(0xFF0B1018), Color(0xFF0A0E15)],
    accentA: Color(0x3322D3EE),
    accentB: Color(0x33818CF8),
    accentC: Color(0x2934D399),
    textPrimary: Color(0xFFF5F7FA),
    textSecondary: Color(0x9EF5F7FA),
    textTertiary: Color(0x66F5F7FA),
    glassTextPrimary: Color(0xEBF5F7FA),
    glassTextSecondary: Color(0x99F5F7FA),
    glassOverlayWhite: Color(0x0FFFFFFF),
    glassOverlayBlack: Color(0x61000000),
    glassHighlightStrong: Color(0x38FFFFFF),
    glassHighlightSoft: Color(0x14FFFFFF),
    glassHighlightFade: Color(0x00FFFFFF),
    glassPressHighlight: Color(0x2EFFFFFF),
    glassRimTop: Color(0x4DFFFFFF),
    glassRimOther: Color(0x1AFFFFFF),
    glassShadow: Color(0x66000000),
    glassOpaqueSheen: Color(0x0AFFFFFF),
    opaqueSurfaceGradient: <Color>[Color(0xFF1A212C), Color(0xFF10151D)],
    focusRim: Color(0x8C22D3EE),
    surface: Color(0xFF151B24),
    border: Color(0x24FFFFFF),
    divider: Color(0x1AFFFFFF),
    chipSelected: Color(0x2634D399),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 非玻璃区域常用的手写字重组合
  TextStyle get mono => AppType.footnote.copyWith(
        fontFamilyFallback: AppType.monoFallback,
        color: glassTextPrimary,
      );
}
