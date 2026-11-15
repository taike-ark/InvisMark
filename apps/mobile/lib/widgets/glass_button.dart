// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 按钮：主按钮是实色青绿渐变（规范 §5：CTA 不用玻璃，保证可读性），
// 次按钮是玻璃胶囊。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'glass_container.dart';

/// 主操作按钮：H56 全宽实色渐变胶囊，按下亮度 +8%（不叠玻璃）。
class GlassPrimaryButton extends StatefulWidget {
  const GlassPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  /// 语义标签应包含动作与对象，如"为选中的图片嵌入水印"（§8）。
  final String? semanticsLabel;

  @override
  State<GlassPrimaryButton> createState() => _GlassPrimaryButtonState();
}

class _GlassPrimaryButtonState extends State<GlassPrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setPressed(bool pressed) {
    if (!_enabled || _pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  void _handleTap() {
    if (!_enabled) {
      return;
    }
    HapticFeedback.lightImpact();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final IconData? icon = widget.icon;

    final Widget leading = widget.loading
        ? const SizedBox(
            width: AppIconSize.sm,
            height: AppIconSize.sm,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppBrand.onCta),
          )
        : (icon == null
            ? const SizedBox.shrink()
            : Icon(icon, size: AppIconSize.md, color: AppBrand.onCta));

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticsLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enabled ? _handleTap : null,
        onTapDown: _enabled ? (TapDownDetails _) => _setPressed(true) : null,
        onTapUp: _enabled ? (TapUpDetails _) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressScale : 1,
          duration: AppMotion.press,
          curve: AppMotion.pressCurve,
          child: SizedBox(
            width: double.infinity,
            height: AppLayout.primaryButtonHeight,
            child: AnimatedContainer(
              duration: AppMotion.highlight,
              curve: AppMotion.enterCurve,
              // 按压提亮：白色遮罩 8%（亮度 +8% 的等效实现）
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.full),
                color: _pressed ? AppBrand.ctaPressWash : AppBrand.clear,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.full),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: AppBrand.ctaGradient,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _enabled ? AppBrand.ctaShadow : AppBrand.clear,
                    offset: AppShadow.ctaOffset,
                    blurRadius: AppShadow.ctaBlur,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null || widget.loading) ...<Widget>[
                    leading,
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.headline.copyWith(
                        color: _enabled ? AppBrand.onCta : AppBrand.onCta.withAlpha(AppAlpha.disabled),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 次要动作：玻璃胶囊按钮 H48，按下白 α +.05（§5）。
class GlassSecondaryButton extends StatelessWidget {
  const GlassSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// true = 撑满可用宽度；false = 内容自适应（用于并排两个次按钮）。
  final bool expanded;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final IconData? icon = this.icon;
    final bool enabled = onPressed != null;

    final Widget content = SizedBox(
      height: AppLayout.secondaryButtonHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: AppIconSize.sm,
              color: enabled ? palette.glassTextPrimary : palette.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.headline.copyWith(
                color: enabled ? palette.glassTextPrimary : palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      child: GlassContainer(
        radius: AppRadius.full,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        pressScale: AppMotion.pillPressScale,
        onTap: enabled ? onPressed : null,
        child: content,
      ),
    );
  }
}
