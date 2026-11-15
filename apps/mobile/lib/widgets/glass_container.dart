// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 液态玻璃核心（规范 §2 五层材质 / §5 组件规格 / §7 性能与三档降级）。
//
// 结构（自外向内）：
//   RepaintBoundary（隔离重绘）
//     └ BoxShadow（Z4 投影）
//        └ ClipRRect（半径来自 Token）
//           └ BackdropFilter —— 仅 full/lite；opaque 档【完全不创建】
//              └ Stack
//                 ├ CustomPaint（Z1 基体 + 镜面高光 + Z2 边缘描边 + 焦点边缘光）
//                 └ content（Z3 内容）
//
// 硬规则：
//   1. 图片/成图区域禁止使用本组件，玻璃只出现在图片边界之外（§1.2 第 3 条）。
//   2. 一屏玻璃块数 ≤ AppLayout.maxGlassPerScreen（含 TabBar）。
//   3. opaque 档不走 BackdropFilter，改半透明/不透明渐变底，保证低端机可用。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// 玻璃档位作用域：App 根部按设置/性能解析一次，子树统一读取。
/// 未挂载时默认 [GlassTier.full]。
class AdaptiveGlassScope extends InheritedWidget {
  const AdaptiveGlassScope({
    super.key,
    required this.tier,
    required super.child,
  });

  final GlassTier tier;

  /// 订阅式读取：tier 变化会触发调用方重建。
  static GlassTier of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveGlassScope>()?.tier ??
      GlassTier.full;

  /// 非订阅式读取（用于事件回调里取当前档位）。
  static GlassTier read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AdaptiveGlassScope>()?.tier ??
      GlassTier.full;

  @override
  bool updateShouldNotify(AdaptiveGlassScope oldWidget) => oldWidget.tier != tier;
}

/// 一块液态玻璃。内容尺寸由子组件决定；`onTap`/`onLongPress` 存在时自动带按压反馈。
class GlassContainer extends StatefulWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.padding = const EdgeInsets.all(AppSpacing.glassInner),
    this.tier,
    this.onTap,
    this.onLongPress,
    this.pressScale,
    this.focus = false,
    this.tint,
    this.semanticsLabel,
  });

  final Widget child;

  /// 圆角，取自 AppRadius。
  final double radius;

  final EdgeInsetsGeometry padding;

  /// 显式档位（覆盖 Scope）。默认 null → 跟随 [AdaptiveGlassScope]。
  final GlassTier? tier;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下缩放比例，默认 AppMotion.pressScale；胶囊传 pillPressScale。
  final double? pressScale;

  /// 焦点玻璃：每屏只允许 1 块（§7.1）。启用折射 shader 前用边缘光标记唯一的"焦点"。
  final bool focus;

  /// 着色调（如分享风险条用琥珀）。
  final Color? tint;

  /// 无障碍语义标签，必须包含"动作 + 对象"（§8）。
  final String? semanticsLabel;

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: AppMotion.press,
  );

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      // Reduce Motion：无 spring 形变，直接淡入式反馈（§6）
      _press.value = pressed ? 1 : 0;
      return;
    }
    if (pressed) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  void _handleTap() {
    // 轻震是"命中反馈"的一部分，但只在有点击回调时触发
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final GlassTier tier = widget.tier ?? AdaptiveGlassScope.of(context);
    final GlassMaterialSpec spec = GlassMaterialSpec.of(tier);
    final BorderRadius radius = BorderRadius.circular(widget.radius);
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Z1 + Z2：玻璃基体与边缘高光画在内容下方（不额外嵌 Container，§7.3）
    final Widget layered = Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _press,
              builder: (BuildContext context, Widget? child) => CustomPaint(
                painter: _GlassSurfacePainter(
                  palette: palette,
                  tier: tier,
                  radius: widget.radius,
                  focus: widget.focus,
                  tint: widget.tint,
                  pressProgress: (_interactive && spec.animatesHighlight && !reduceMotion)
                      ? _press.value
                      : null,
                ),
              ),
            ),
          ),
        ),
        // Z3 内容
        Padding(padding: widget.padding, child: widget.child),
      ],
    );

    // 只有 full/lite 才创建 BackdropFilter；opaque 档零模糊开销。
    Widget surface = layered;
    if (spec.usesBackdropFilter) {
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: spec.blurSigma,
            sigmaY: spec.blurSigma,
            tileMode: ui.TileMode.clamp,
          ),
          child: layered,
        ),
      );
    }

    // Z4 投影在裁剪层之外，避免被 ClipRRect 吃掉
    final Widget shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.glassShadow,
            offset: AppShadow.glassOffset,
            blurRadius: AppShadow.glassBlur,
            spreadRadius: AppShadow.glassSpread,
          ),
        ],
      ),
      child: surface,
    );

    if (!_interactive) {
      return RepaintBoundary(child: shadowed);
    }

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null ? null : _handleTap,
        onLongPress: widget.onLongPress,
        onTapDown: (TapDownDetails _) => _setPressed(true),
        onTapUp: (TapUpDetails _) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedBuilder(
          animation: _press,
          child: shadowed,
          builder: (BuildContext context, Widget? child) {
            final double curve = AppMotion.pressCurve.transform(_press.value);
            final double target = widget.pressScale ?? AppMotion.pressScale;
            final double scale = 1 - (1 - target) * curve;
            return Transform.scale(
              scale: scale,
              child: RepaintBoundary(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );
  }
}

/// 玻璃表面绘制：基体双 overlay → 左上镜面 → 右下环境光 → 着色 → 按压高光 → 边缘描边。
class _GlassSurfacePainter extends CustomPainter {
  const _GlassSurfacePainter({
    required this.palette,
    required this.tier,
    required this.radius,
    required this.focus,
    required this.tint,
    required this.pressProgress,
  });

  final AppPalette palette;
  final GlassTier tier;
  final double radius;
  final bool focus;
  final Color? tint;

  /// null = 静态高光（lite / opaque / Reduce Motion）；0..1 = 实时高光扫过进度。
  final double? pressProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final Rect rect = Offset.zero & size;
    final RRect body = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    if (tier == GlassTier.opaque) {
      // 不透明渐变卡片：保留圆角与层级，视觉不塌（§7.2）
      canvas.drawRRect(
        body,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.bottomRight,
            palette.opaqueSurfaceGradient,
          ),
      );
      canvas.drawRRect(body, Paint()..color = palette.glassOpaqueSheen);
    } else {
      // 双 overlay：暗色先铺黑（.38），白色覆盖其上（.06）；亮色反之权重
      canvas.drawRRect(body, Paint()..color = palette.glassOverlayBlack);
      canvas.drawRRect(body, Paint()..color = palette.glassOverlayWhite);
    }

    // 左上镜面高光（radial-gradient 120% 80% at 15% 0%）
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(rect.width * 0.15, -rect.height * 0.10),
          rect.longestSide * 0.90,
          <Color>[palette.glassHighlightStrong, palette.glassHighlightFade],
        ),
    );

    // 右下环境光（radial-gradient 100% 60% at 85% 100%）
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(rect.width * 0.85, rect.height * 1.0),
          rect.longestSide * 0.80,
          <Color>[palette.glassHighlightSoft, palette.glassHighlightFade],
        ),
    );

    // 着色调（如警示琥珀）：只在有色时才叠一层淡洗色
    final Color? tint = this.tint;
    if (tint != null) {
      canvas.drawRRect(body, Paint()..color = tint.withAlpha(AppAlpha.tintWash));
    }

    // 按压高光扫过：位置随进度从左上滑向右下，亮度中段最强（§6「按下高光增强」）
    final double? progress = pressProgress;
    if (progress != null) {
      final double t = progress.clamp(0.0, 1.0).toDouble();
      final double glow = 1 - (2 * t - 1).abs();
      final int alpha = (AppAlpha.pressSweep * glow).round();
      canvas.drawRRect(
        body,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(rect.width * (0.10 + 0.80 * t), rect.height * (0.05 + 0.40 * t)),
            rect.longestSide * 0.70,
            <Color>[
              palette.glassPressHighlight.withAlpha(alpha),
              palette.glassHighlightFade,
            ],
          ),
      );
    }

    // Z2 边缘透镜：顶部亮、其余暗（1px 内描边）
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          <Color>[palette.glassRimTop, palette.glassRimOther],
        ),
    );

    // 焦点玻璃：2px 青绿边缘光（真正的 uv 折射 shader 在 M3 用 FragmentProgram 接入）
    if (focus) {
      canvas.drawRRect(
        body.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = palette.focusRim
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, AppShadow.focusRimBlur),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassSurfacePainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.tier != tier ||
      oldDelegate.radius != radius ||
      oldDelegate.focus != focus ||
      oldDelegate.tint != tint ||
      oldDelegate.pressProgress != pressProgress;
}
