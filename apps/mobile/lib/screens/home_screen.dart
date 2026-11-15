// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 首页（规范 §4.1）：最近一张图 + 大按钮「选图嵌入」+ 最近任务。
//
// 玻璃预算（§1.2 / §7.1，同屏 ≤ 3 块）：
//   ① 顶部标题胶囊   ② 主嵌入卡（本屏唯一焦点玻璃）   ③ 悬浮 TabBar（在 app.dart）
// 因此「检测入口」「配额」「最近任务列表」都放在非玻璃区域，避免超预算。

import 'package:flutter/material.dart';

import '../models/trace.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_container.dart';
import 'result_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenDetect,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenDetect;
  final VoidCallback onOpenSettings;

  /// 演示配额：M3 接 GET /v1/quota 后替换
  static const int quotaUsed = 128;
  static const int quotaLimit = 1000;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final AppPalette palette = AppPalette.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppLayout.scrollBottomInset,
      ),
      children: <Widget>[
        _HeaderPill(onOpenSettings: onOpenSettings),
        const SizedBox(height: AppSpacing.xl),
        const _RecentImageArea(),
        const SizedBox(height: AppSpacing.xl),
        GlassCard(
          focus: true,
          onTap: () => _handleEmbedTap(context),
          semanticsLabel: '为选中的图片嵌入水印',
          title: '选择图片嵌入水印',
          subtitle: '支持 200 张批量 · 输出 PNG 无损 / JPEG 95',
          padding: const EdgeInsets.all(AppSpacing.glassInner),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: AppLayout.navPillHeight,
                    height: AppLayout.navPillHeight,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: AppBrand.ctaGradient),
                    ),
                    child: const Icon(Icons.add, color: AppBrand.onCta, size: AppIconSize.md),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '从相册选择，或在相机里现场拍摄',
                      style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // 玻璃内部不再叠玻璃：配额条用普通进度条 + 说明文字
              Row(
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: quotaUsed / quotaLimit,
                        minHeight: AppSpacing.sm,
                        backgroundColor: palette.glassOverlayWhite,
                        color: AppBrand.ctaEnd,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    '本月 $quotaUsed / $quotaLimit',
                    style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // 非玻璃入口：本屏玻璃预算已用满
        _FlatActionRow(
          icon: Icons.search,
          title: '输入追溯码 / 选图检测',
          subtitle: '从被压缩或截图的图片里恢复 trace_id',
          onTap: onOpenDetect,
        ),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '最近任务',
                style: AppType.title2.copyWith(color: palette.textPrimary),
              ),
            ),
            Text(
              state.recentTasks.isEmpty ? '空' : '${state.recentTasks.length} 条',
              style: AppType.footnote.copyWith(color: palette.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!state.hasRecentTasks)
          _EmptyRecentTasks(palette: palette)
        else
          for (final RecentTask task in state.recentTasks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _RecentTaskTile(
                task: task,
                palette: palette,
                onTap: () => _openResult(context, EmbedResult(
                  assetId: '',
                  traceId: task.traceId,
                  quality: task.quality,
                  imageUrl: task.imageUrl,
                  embeddedAt: task.embeddedAt,
                )),
              ),
            ),
        if (state.errorMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _ErrorStrip(message: state.errorMessage!, palette: palette),
        ],
      ],
    );
  }

  /// 选图：原生相册/相机需要插件（M3），当前用弹窗说明 + 演示数据走通流程。
  Future<void> _handleEmbedTap(BuildContext context) async {
    final AppState state = AppStateScope.read(context);
    final bool? useDemo = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppBrand.clear,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => const _PickerSheet(),
    );
    if (!context.mounted || useDemo != true) {
      return;
    }
    state.loadDemoEmbed();
    _openResult(context, state.lastEmbed);
  }

  void _openResult(BuildContext context, EmbedResult? result) {
    if (result == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext routeContext) => ResultScreen(result: result)),
    );
  }
}

/// ① 标题胶囊（本屏第 1 块玻璃）
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return GlassContainer(
      radius: AppRadius.full,
      padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.xs),
      child: SizedBox(
        height: AppLayout.navPillHeight,
        child: Row(
          children: <Widget>[
            Text(
              '隐迹 InvisMark',
              style: AppType.headline.copyWith(color: palette.glassTextPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '· 张*',
              style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
            ),
            const Spacer(),
            _IconAction(
              icon: Icons.settings_outlined,
              semanticsLabel: '打开设置',
              color: palette.glassTextSecondary,
              onTap: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// 44×44 的图标按钮（玻璃内不叠玻璃，所以只是可点击的图标）
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.semanticsLabel,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppLayout.minTouchTarget,
          height: AppLayout.minTouchTarget,
          child: Icon(icon, size: AppIconSize.md, color: color),
        ),
      ),
    );
  }
}

/// 图片区域：⚠️ 禁止叠加任何玻璃（§1.2 第 3 条）。
/// 这里将来放"最近一张图"的 1/4 静态快照；玻璃只出现在它的边界之外。
class _RecentImageArea extends StatelessWidget {
  const _RecentImageArea();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    // 纯像素区域：无模糊、无渐变描边、无玻璃
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: AppLayout.heroHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[palette.surface, palette.backgroundGradient.last],
            ),
            border: Border.all(color: palette.border),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.image_outlined, size: AppIconSize.xl, color: palette.textTertiary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '最近一张图（缩略图不参与模糊）',
                  style: AppType.footnote.copyWith(color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 非玻璃入口行（检测 / 更多）
class _FlatActionRow extends StatelessWidget {
  const _FlatActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(icon, size: AppIconSize.md, color: palette.textPrimary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppType.headline.copyWith(color: palette.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: AppType.footnote.copyWith(color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: AppIconSize.md, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentTasks extends StatelessWidget {
  const _EmptyRecentTasks({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // 空态用非玻璃面：再放一块玻璃就超预算了
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            Icon(Icons.inbox_outlined, size: AppIconSize.lg, color: palette.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '还没有嵌入记录',
              style: AppType.body.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '选一张图，第一个 trace_id 会出现在这里',
              textAlign: TextAlign.center,
              style: AppType.footnote.copyWith(color: palette.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTaskTile extends StatelessWidget {
  const _RecentTaskTile({
    required this.task,
    required this.palette,
    required this.onTap,
  });

  final RecentTask task;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = task.imageUrl;

    return Semantics(
      button: true,
      label: '查看溯源记录 ${task.traceId}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                // 缩略图：静态、不参与模糊（§4.6），也绝不被玻璃覆盖
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: AppLayout.minTouchTarget,
                    height: AppLayout.minTouchTarget,
                    child: imageUrl == null
                        ? _thumbnailFallback()
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                                _thumbnailFallback(),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.traceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.footnote.copyWith(
                          color: palette.textPrimary,
                          fontFamilyFallback: AppType.monoFallback,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${formatTimestamp(task.embeddedAt)} · ${task.quality.psnrLabel}',
                        style: AppType.footnote.copyWith(color: palette.textTertiary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: AppIconSize.md, color: palette.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailFallback() => DecoratedBox(
        decoration: BoxDecoration(color: palette.backgroundGradient.last),
        child: Icon(Icons.image_outlined, size: AppIconSize.sm, color: palette.textTertiary),
      );
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.palette});

  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppBrand.danger.withAlpha(AppAlpha.tintWash),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, size: AppIconSize.sm, color: AppBrand.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppType.footnote.copyWith(color: palette.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选图来源说明 + 演示入口（原生插件 M3 接入）
class _PickerSheet extends StatelessWidget {
  const _PickerSheet();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double bottomInset = MediaQuery.maybeOf(context)?.viewPadding.bottom ?? 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.page,
          AppSpacing.page,
          AppSpacing.page + bottomInset,
        ),
        child: GlassContainer(
          radius: AppRadius.xl,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '选择图片来源',
                style: AppType.title2.copyWith(color: palette.glassTextPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                // TODO(M3): 接入原生插件 —— image_picker（相册/相机）、camera（取景），
                // 接入后这里换成真实的 bytes，再调用 AppState.embedImage()。
                '相册与相机需要原生插件（M3 接入 image_picker / camera）。'
                '当前脚手架用演示数据走通完整流程。',
                style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              GlassPrimaryButton(
                label: '用演示数据继续',
                icon: Icons.science_outlined,
                semanticsLabel: '使用演示数据走通嵌入流程',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassSecondaryButton(
                label: '取消',
                semanticsLabel: '取消选图',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
