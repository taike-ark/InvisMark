// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 玻璃卡片（规范 §5 GlassCard）：圆角 lg 28、内距 20、blur 随档位、
// 按下 scale .97 且投影收紧。文字用 §2 Z3 的玻璃文字色。

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass_container.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.focus = false,
    this.tint,
    this.radius = AppRadius.lg,
    this.padding = const EdgeInsets.all(AppSpacing.glassInner),
    this.semanticsLabel,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 焦点玻璃：每屏只允许 1 块（§7.1）。
  final bool focus;

  final Color? tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final String? title = this.title;
    final String? subtitle = this.subtitle;
    final Widget? trailing = this.trailing;

    return GlassContainer(
      radius: radius,
      padding: padding,
      focus: focus,
      tint: tint,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsLabel: semanticsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: AppType.title2.copyWith(color: palette.glassTextPrimary),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (subtitle != null) ...<Widget>[
            Text(
              subtitle,
              // 玻璃上的辅助文字不得小于 footnote 13pt 且 α ≥ .6（§3.3）
              style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}
