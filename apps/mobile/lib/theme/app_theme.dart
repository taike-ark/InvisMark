// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// ThemeData 亮/暗两套。所有取值来自 tokens.dart，这里只做"Token → Material 主题"的映射。

import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class AppTheme {
  static final ThemeData light = _build(AppPalette.light);
  static final ThemeData dark = _build(AppPalette.dark);

  static ThemeData _build(AppPalette palette) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppBrand.ctaStart,
      brightness: palette.brightness,
    ).copyWith(
      primary: AppBrand.ctaStart,
      onPrimary: AppBrand.onCta,
      secondary: AppBrand.trace,
      onSecondary: AppBrand.onTrace,
      error: AppBrand.danger,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.surface,
      outline: palette.border,
    );

    final ThemeData base = ThemeData(brightness: palette.brightness, useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppBrand.clear,
      canvasColor: palette.surface,
      dividerColor: palette.divider,
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppBrand.clear,
      textTheme: base.textTheme.merge(_textTheme(palette)),
      primaryTextTheme: base.primaryTextTheme.merge(_textTheme(palette)),
      appBarTheme: AppBarTheme(
        backgroundColor: AppBrand.clear,
        surfaceTintColor: AppBrand.clear,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: palette.textPrimary,
        titleTextStyle: AppType.headline.copyWith(color: palette.textPrimary),
      ),
      iconTheme: IconThemeData(color: palette.textPrimary, size: AppIconSize.md),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: AppType.footnote.copyWith(color: palette.textTertiary),
        labelStyle: AppType.footnote.copyWith(color: palette.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppBrand.ctaEnd, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surface,
        contentTextStyle: AppType.footnote.copyWith(color: palette.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppBrand.clear,
        surfaceTintColor: AppBrand.clear,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppBrand.ctaEnd,
        linearMinHeight: AppLayout.progressBarHeight,
      ),
    );
  }

  static TextTheme _textTheme(AppPalette palette) => TextTheme(
        displayLarge: AppType.display.copyWith(color: palette.textPrimary),
        displayMedium: AppType.display.copyWith(color: palette.textPrimary),
        titleLarge: AppType.title1.copyWith(color: palette.textPrimary),
        titleMedium: AppType.title2.copyWith(color: palette.textPrimary),
        titleSmall: AppType.headline.copyWith(color: palette.textPrimary),
        bodyLarge: AppType.body.copyWith(color: palette.textPrimary),
        bodyMedium: AppType.body.copyWith(color: palette.textSecondary),
        bodySmall: AppType.footnote.copyWith(color: palette.textSecondary),
        labelLarge: AppType.headline.copyWith(color: palette.textPrimary),
        labelMedium: AppType.footnote.copyWith(color: palette.textSecondary),
        labelSmall: AppType.caption.copyWith(color: palette.textTertiary),
      );
}
