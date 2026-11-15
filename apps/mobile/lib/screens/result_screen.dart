// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 嵌入结果（规范 §4.4）：成图全屏 + 底部玻璃抽屉（质量指标 / trace_id / 三段动作）。
//
// 硬规则：
//   1. 成图区域【零玻璃、零模糊】：玻璃只出现在图片边界之外（§1.2 第 3 条）。
//   2. 本屏常驻玻璃 3 块：① 顶部返回胶囊 ② 分享风险提示条 ③ 底部抽屉。
//   3. 点「分享」先弹风险 sheet，文案不承诺"保证可检出"。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trace.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/glass_container.dart';
import '../widgets/risk_banner.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.result});

  final EmbedResult result;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  /// 双指缩放只作用于图片层，不重建玻璃（§4.4）
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: AppMotion.toast),
    );
  }

  Future<void> _copyTraceLink() async {
    // 链接由客户端按配置的 API 地址生成，避免硬编码域名
    final String link = AppStateScope.read(context).client.traceUrl(widget.result.traceId);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) {
      return;
    }
    _toast('溯源链接已复制：${widget.result.traceId}');
  }

  Future<void> _copyTraceId() async {
    await Clipboard.setData(ClipboardData(text: widget.result.traceId));
    if (!mounted) {
      return;
    }
    _toast('trace_id 已复制');
  }

  /// 分享前必须先过风险提示（§4.4 / §9 验收清单）
  Future<void> _share() async {
    final bool confirmed = await showShareRiskSheet(context);
    if (!mounted || !confirmed) {
      return;
    }
    // TODO(M3): 接入原生分享插件（share_plus 或平台通道），并优先分享原图。
    _toast('分享需要原生插件（M3 接入），当前可用「复制溯源链接」');
  }

  void _saveToGallery() {
    // TODO(M3): 接入相册写入插件（Android MediaStore / iOS PHPhotoLibrary）。
    _toast('保存到相册需要原生插件（M3 接入）');
  }

  void _openProof() {
    // TODO(M3): 接入 url_launcher 打开 /v1/reports 生成的证据包。
    _toast('证据包在浏览器打开（M3 接入 url_launcher）');
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final EmbedResult result = widget.result;

    return Scaffold(
      backgroundColor: AppBrand.clear,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _ImageViewer(result: result, zoom: _zoom, palette: palette)),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      AppSpacing.md,
                      AppSpacing.page,
                      0,
                    ),
                    child: _NavPill(
                      title: '嵌入结果',
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        AppSpacing.md,
                        AppSpacing.page,
                        AppSpacing.page,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // ② 分享风险提示条（独立玻璃块，不与抽屉嵌套）
                          RiskBanner(onTap: _share),
                          const SizedBox(height: AppSpacing.glassGap),
                          // ③ 底部抽屉
                          _ResultDrawer(
                            result: result,
                            palette: palette,
                            onSave: _saveToGallery,
                            onShare: _share,
                            onCopyLink: _copyTraceLink,
                            onCopyTraceId: _copyTraceId,
                            onOpenProof: _openProof,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 成图区域：⚠️ 这里禁止叠加任何玻璃/模糊层，只有图片本身（可双指缩放）。
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.result,
    required this.zoom,
    required this.palette,
  });

  final EmbedResult result;
  final TransformationController zoom;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final String? url = result.imageUrl;

    return GestureDetector(
      onDoubleTap: () => zoom.value = Matrix4.identity(),
      child: InteractiveViewer(
        transformationController: zoom,
        minScale: 1,
        maxScale: 4,
        child: SizedBox.expand(
          child: ColoredBox(
            color: palette.backgroundGradient.first,
            child: url == null
                ? _placeholder()
                : Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                        _placeholder(),
                    loadingBuilder: (
                      BuildContext context,
                      Widget child,
                      ImageChunkEvent? progress,
                    ) =>
                        progress == null
                            ? child
                            : const Center(
                                child: SizedBox(
                                  width: AppLayout.progressRingSize / 2,
                                  height: AppLayout.progressRingSize / 2,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.image_outlined, size: AppIconSize.xl, color: palette.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '成图预览（演示占位，接入后端后显示 image_url）',
              style: AppType.footnote.copyWith(color: palette.textTertiary),
            ),
          ],
        ),
      );
}

/// ① 顶部返回胶囊（本屏第 1 块玻璃）
class _NavPill extends StatelessWidget {
  const _NavPill({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: GlassContainer(
        radius: AppRadius.full,
        padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.xl),
        child: SizedBox(
          height: AppLayout.navPillHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                button: true,
                label: '返回上一页',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: SizedBox(
                    width: AppLayout.minTouchTarget,
                    height: AppLayout.minTouchTarget,
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: AppIconSize.sm,
                      color: palette.glassTextPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: AppType.headline.copyWith(color: palette.glassTextPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部抽屉：质量指标 + trace_id + 三段动作 + 证据包入口
class _ResultDrawer extends StatelessWidget {
  const _ResultDrawer({
    required this.result,
    required this.palette,
    required this.onSave,
    required this.onShare,
    required this.onCopyLink,
    required this.onCopyTraceId,
    required this.onOpenProof,
  });

  final EmbedResult result;
  final AppPalette palette;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onCopyLink;
  final VoidCallback onCopyTraceId;
  final VoidCallback onOpenProof;

  @override
  Widget build(BuildContext context) {
    final EmbedQuality quality = result.quality;

    return GlassContainer(
      radius: AppRadius.xl,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 拖拽把手（非玻璃）
          Center(
            child: Container(
              width: AppLayout.sheetHandleWidth,
              height: AppLayout.sheetHandleHeight,
              decoration: BoxDecoration(
                color: palette.glassRimOther,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricTile(label: 'PSNR', value: quality.psnrLabel, palette: palette),
              ),
              Expanded(
                child: _MetricTile(label: 'SSIM', value: quality.ssimLabel, palette: palette),
              ),
              Expanded(
                child: _MetricTile(
                  label: '画质',
                  value: quality.meetsBaseline ? '达标' : '偏低',
                  palette: palette,
                  highlight: !quality.meetsBaseline,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // trace_id：等宽字体，点击整行复制
          Semantics(
            button: true,
            label: '复制 trace_id ${result.traceId}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCopyTraceId,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.glassOverlayWhite,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'trace_id',
                        style: AppType.footnote.copyWith(
                          color: palette.glassTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          result.traceId.isEmpty ? '—' : result.traceId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.footnote.copyWith(
                            color: palette.glassTextPrimary,
                            fontFamilyFallback: AppType.monoFallback,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.copy_rounded,
                        size: AppIconSize.sm,
                        color: palette.glassTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '嵌入时间 ${formatTimestamp(result.embeddedAt)} · '
            '证据有效期至 ${formatTimestamp(result.expiresAt)}',
            style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _ActionTile(
                  icon: Icons.download_rounded,
                  label: '保存到相册',
                  semanticsLabel: '保存成图到相册',
                  palette: palette,
                  onTap: onSave,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionTile(
                  icon: Icons.ios_share,
                  label: '分享',
                  semanticsLabel: '分享成图（会先提示渠道风险）',
                  palette: palette,
                  onTap: onShare,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionTile(
                  icon: Icons.link_rounded,
                  label: '复制链接',
                  semanticsLabel: '复制溯源链接',
                  palette: palette,
                  onTap: onCopyLink,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // 证据包入口：蓝紫色（溯源语义），行内不做玻璃嵌套
          Semantics(
            button: true,
            label: '查看证据包',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenProof,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.verified_outlined, size: AppIconSize.sm, color: AppBrand.trace),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '查看证据包（证明链报告）',
                        style: AppType.footnote.copyWith(color: AppBrand.trace),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: AppIconSize.md,
                      color: palette.glassTextSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.palette,
    this.highlight = false,
  });

  final String label;
  final String value;
  final AppPalette palette;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.headline.copyWith(
            color: highlight ? AppBrand.warn : palette.glassTextPrimary,
            fontFamilyFallback: AppType.monoFallback,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppLayout.minTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.glassOverlayWhite,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: AppIconSize.md, color: palette.glassTextPrimary),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppType.footnote.copyWith(color: palette.glassTextPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
