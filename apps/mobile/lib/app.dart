// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 页面骨架：IndexedStack 保留三页状态 + 悬浮玻璃 TabBar + 玻璃档位解析。
//
// 三档降级入口在这里：偏好 + 系统「降低透明度/高对比」→ chooseGlassTier →
// AdaptiveGlassScope 下发到每一块 GlassContainer（glass_container.dart）。
// 冷启动首帧强制 Opaque，200ms 后切到真实档位（规范 §7.1）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/detect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';
import 'widgets/glass_container.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _booted = false;
  Timer? _coldStartTimer;

  @override
  void initState() {
    super.initState();
    // 首帧不出现玻璃动画：先 Opaque，随后再启用真实档位
    _coldStartTimer = Timer(AppLayout.coldStartOpaqueHold, () {
      if (!mounted) {
        return;
      }
      setState(() => _booted = true);
    });
  }

  @override
  void dispose() {
    _coldStartTimer?.cancel();
    super.dispose();
  }

  void _select(int index) {
    if (_index == index) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final MediaQueryData? media = MediaQuery.maybeOf(context);

    // 「降低透明度」在 Flutter 没有独立通道，用 highContrast / 省电模式近似
    final GlassTier resolved = state.resolveTier(
      reduceTransparency: media?.highContrast ?? false,
    );
    final GlassTier tier = _booted ? resolved : GlassTier.opaque;

    return AdaptiveGlassScope(
      tier: tier,
      child: AppBackdrop(
        child: Scaffold(
          backgroundColor: AppBrand.clear, // 背景由 AppBackdrop 画，Scaffold 保持透明
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                HomeScreen(
                  onOpenDetect: () => _select(1),
                  onOpenSettings: () => _select(2),
                ),
                const DetectScreen(),
                const SettingsScreen(),
              ],
            ),
          ),
          bottomNavigationBar: _GlassTabBar(index: _index, onSelect: _select),
        ),
      ),
    );
  }
}

/// 页面背景：底色渐变 + 三处品牌色光斑（玻璃的折射来源，本身不是玻璃）
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.backgroundGradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _blob(palette.accentA, const Alignment(-0.95, -1.0), AppLayout.backdropBlobA),
          _blob(palette.accentB, const Alignment(1.0, -0.65), AppLayout.backdropBlobB),
          _blob(palette.accentC, const Alignment(0.05, 1.05), AppLayout.backdropBlobC),
          child,
        ],
      ),
    );
  }

  Widget _blob(Color color, Alignment alignment, double size) => Align(
        alignment: alignment,
        child: IgnorePointer(
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[color, AppBrand.clear],
                ),
              ),
            ),
          ),
        ),
      );
}

class _TabItem {
  const _TabItem({required this.label, required this.icon, required this.activeIcon});

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// ③ 悬浮 TabBar（每屏的第 3 块玻璃；整个 bar 只有一块）
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const List<_TabItem> items = <_TabItem>[
    _TabItem(label: '首页', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    _TabItem(
      label: '检测',
      icon: Icons.center_focus_weak,
      activeIcon: Icons.center_focus_strong,
    ),
    _TabItem(label: '我的', icon: Icons.person_outline, activeIcon: Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppLayout.tabBarBottomInset),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: GlassContainer(
          radius: AppRadius.full,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: SizedBox(
            height: AppLayout.tabBarHeight,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _TabButton(
                      item: items[i],
                      selected: index == i,
                      palette: palette,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final _TabItem item;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: AppMotion.tab,
            curve: AppMotion.tabCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? palette.chipSelected : AppBrand.clear,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: AppIconSize.md,
                  color: selected ? AppBrand.ctaEnd : palette.glassTextSecondary,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  // §3.3 建议 TabBar 用 caption 11pt，但与"玻璃上 ≥13pt"冲突，取 13pt
                  item.label,
                  style: AppType.footnote.copyWith(
                    color: selected ? AppBrand.ctaEnd : palette.glassTextSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
