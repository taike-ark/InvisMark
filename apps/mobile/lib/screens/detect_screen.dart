// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 检测 / 溯源（规范 §4.5）：选图检测，命中与未检出两态。
//
// 玻璃预算（≤ 3）：① 顶部标题胶囊 ② 状态卡 ③ 悬浮 TabBar。
// 玻璃卡内不再嵌玻璃按钮（避免"玻璃套玻璃"），卡内动作用扁平按钮。
// 取景区是图片区域：零玻璃、零模糊。

import 'package:flutter/material.dart';

import '../models/trace.dart';
import '../services/native_media.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_container.dart';

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});

  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  bool _showReasons = false;

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: AppMotion.toast),
    );
  }

  Future<void> _pickAndDetect() async {
    final AppState state = AppStateScope.read(context);
    PickedImage? picked;
    try {
      picked = await NativeMedia.pickImage();
    } on NativeMediaException catch (error) {
      if (!mounted) {
        return;
      }
      if (!error.cancelled) {
        state.reportError(error.message);
        _toast(error.message);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    await state.detectImage(bytes: picked.bytes, filename: picked.name);
    if (!mounted) {
      return;
    }
    final String message = switch (state.detectStatus) {
      DetectStatus.found => '检出追溯码：${state.lastTrace?.traceId ?? ''}',
      DetectStatus.notFound => '未在该图片中检出有效追溯码',
      DetectStatus.failed => state.errorMessage ?? '检测失败',
      _ => '检测完成',
    };
    _toast(message);
  }

  void _manualReview() {
    // TODO(M3): 提交人工复核工单（POST /v1/extracts + 附件）。
    _toast('人工复核工单待 M3 接入');
  }

  void _openProof() {
    // TODO(M3): url_launcher 打开 report_url。
    _toast('证据包在浏览器打开（M3 接入 url_launcher）');
  }

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
        _HeaderPill(
          trailing: state.detectStatus == DetectStatus.idle ? null : '再次检测',
          onTrailingTap: state.resetDetect,
        ),
        const SizedBox(height: AppSpacing.xl),
        const _Viewfinder(),
        const SizedBox(height: AppSpacing.xl),
        _StatusCard(
          status: state.detectStatus,
          trace: state.lastTrace,
          errorMessage: state.errorMessage,
          palette: palette,
          showReasons: _showReasons,
          onToggleReasons: () => setState(() => _showReasons = !_showReasons),
          onPick: _pickAndDetect,
          onReset: AppStateScope.read(context).resetDetect,
          onManualReview: _manualReview,
          onOpenProof: _openProof,
        ),
      ],
    );
  }
}

/// ① 标题胶囊（本屏第 1 块玻璃）
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.trailing, required this.onTrailingTap});

  final String? trailing;
  final VoidCallback onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final String? trailing = this.trailing;

    return GlassContainer(
      radius: AppRadius.full,
      padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.xl),
      child: SizedBox(
        height: AppLayout.navPillHeight,
        child: Row(
          children: <Widget>[
            Icon(Icons.center_focus_strong, size: AppIconSize.sm, color: palette.glassTextPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '检测溯源',
              style: AppType.headline.copyWith(color: palette.glassTextPrimary),
            ),
            const Spacer(),
            if (trailing != null)
              Semantics(
                button: true,
                label: trailing,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTrailingTap,
                  child: SizedBox(
                    height: AppLayout.minTouchTarget,
                    child: Center(
                      child: Text(
                        trailing,
                        style: AppType.footnote.copyWith(color: AppBrand.ctaEnd),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 取景区：图片区域，零玻璃。四角准星用 CustomPaint 画（不是玻璃材质）。
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: AppLayout.viewfinderHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[palette.surface, palette.backgroundGradient.first],
            ),
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(painter: _CornerMarksPainter(color: AppBrand.ctaEnd)),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    // 规范原文：不支持屏幕翻拍以外的模糊图
                    '不支持屏幕翻拍以外的模糊图',
                    textAlign: TextAlign.center,
                    style: AppType.footnote.copyWith(color: palette.textTertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerMarksPainter extends CustomPainter {
  const _CornerMarksPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppLayout.viewfinderStrokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    const double inset = AppLayout.viewfinderInset;
    const double arm = AppLayout.viewfinderArm;
    final List<Path> paths = <Path>[
      Path()
        ..moveTo(inset, inset + arm)
        ..lineTo(inset, inset)
        ..lineTo(inset + arm, inset),
      Path()
        ..moveTo(size.width - inset - arm, inset)
        ..lineTo(size.width - inset, inset)
        ..lineTo(size.width - inset, inset + arm),
      Path()
        ..moveTo(size.width - inset, size.height - inset - arm)
        ..lineTo(size.width - inset, size.height - inset)
        ..lineTo(size.width - inset - arm, size.height - inset),
      Path()
        ..moveTo(inset + arm, size.height - inset)
        ..lineTo(inset, size.height - inset)
        ..lineTo(inset, size.height - inset - arm),
    ];
    for (final Path path in paths) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerMarksPainter oldDelegate) => oldDelegate.color != color;
}

/// ② 状态卡（本屏第 2 块玻璃）：idle / busy / found / notFound / failed 五态
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.trace,
    required this.errorMessage,
    required this.palette,
    required this.showReasons,
    required this.onToggleReasons,
    required this.onPick,
    required this.onReset,
    required this.onManualReview,
    required this.onOpenProof,
  });

  final DetectStatus status;
  final TraceResult? trace;
  final String? errorMessage;
  final AppPalette palette;
  final bool showReasons;
  final VoidCallback onToggleReasons;
  final VoidCallback onPick;
  final VoidCallback onReset;
  final VoidCallback onManualReview;
  final VoidCallback onOpenProof;

  /// 未检出三档原因（§4.5）
  static const List<List<String>> reasons = <List<String>>[
    <String>['图中没有水印', '从未嵌入，或嵌入后又经过了不保留水印的处理'],
    <String>['水印已损毁', '强压缩、裁剪、二次编辑导致误码率过高'],
    <String>['图片尺寸过小', '长边 < 800px，或翻拍时水印区域占比太小'],
  ];

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      title: '检测结果',
      subtitle: _subtitle(),
      child: switch (status) {
        DetectStatus.idle => _buildIdle(),
        DetectStatus.busy => _buildBusy(),
        DetectStatus.found => _buildFound(),
        DetectStatus.notFound => _buildNotFound(),
        DetectStatus.failed => _buildFailed(),
      },
    );
  }

  String _subtitle() => switch (status) {
        DetectStatus.idle => '选择一张图，或输入 24 字节追溯码',
        DetectStatus.busy => '正在解码 → 提取比特 → RS 纠错',
        DetectStatus.found => '命中水印，可生成证据包',
        DetectStatus.notFound => '未检出，可人工复核',
        DetectStatus.failed => '请求失败',
      };

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '支持"被压缩 / 截图 / 裁切"过的图片恢复 trace_id。'
          '选图后会直接上传到服务端提取（不走演示数据）。',
          style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        GlassPrimaryButton(
          label: '选图检测',
          icon: Icons.image_search,
          semanticsLabel: '选择一张图片并检测隐含水印',
          onPressed: onPick,
        ),
      ],
    );
  }

  Widget _buildBusy() {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: AppIconSize.md,
          height: AppIconSize.md,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            '正在提取…',
            style: AppType.body.copyWith(color: palette.glassTextSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildFound() {
    final TraceResult found = trace ?? TraceResult.notFound(message: '未检出');
    final TraceUser? user = found.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.verified, size: AppIconSize.sm, color: AppBrand.ctaStart),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '命中 · ${found.confidenceLabel} ${found.confidencePercentLabel}',
                style: AppType.headline.copyWith(color: palette.glassTextPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _KeyValueRow(label: 'trace_id', value: found.traceId ?? '—', palette: palette, mono: true),
        _KeyValueRow(
          label: '归属用户',
          value: user == null ? '—' : '${user.displayName}（${user.userId}）',
          palette: palette,
        ),
        _KeyValueRow(label: '资源编码', value: found.resourceCode ?? '—', palette: palette, mono: true),
        _KeyValueRow(label: '嵌入时间', value: formatTimestamp(found.embeddedAt), palette: palette),
        const SizedBox(height: AppSpacing.lg),
        GlassPrimaryButton(
          label: '生成证据包',
          icon: Icons.verified_outlined,
          semanticsLabel: '为该命中生成证据包',
          onPressed: onOpenProof,
        ),
        const SizedBox(height: AppSpacing.md),
        _FlatButton(label: '继续检测其它图片', palette: palette, onTap: onReset),
      ],
    );
  }

  Widget _buildNotFound() {
    final TraceResult? notFound = trace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.help_outline, size: AppIconSize.sm, color: palette.glassTextPrimary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                // 状态不只靠颜色表达（§8 色觉障碍）
                '未检出',
                style: AppType.headline.copyWith(color: palette.glassTextPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          notFound?.message ?? '这张图里没有可恢复的追溯码。',
          style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          button: true,
          label: showReasons ? '收起可能原因' : '展开可能原因',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleReasons,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Text(
                    '为什么没检出？',
                    style: AppType.footnote.copyWith(color: AppBrand.ctaEnd),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    showReasons ? Icons.expand_less : Icons.expand_more,
                    size: AppIconSize.sm,
                    color: AppBrand.ctaEnd,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showReasons)
          for (final List<String> reason in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reason[0],
                    style: AppType.footnote.copyWith(color: palette.glassTextPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    reason[1],
                    style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                  ),
                ],
              ),
            ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _FlatButton(label: '人工复核', palette: palette, onTap: onManualReview),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _FlatButton(label: '继续检测', palette: palette, onTap: onReset),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, size: AppIconSize.sm, color: AppBrand.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                errorMessage ?? '请求失败，请检查 API 地址与网络',
                style: AppType.footnote.copyWith(color: palette.glassTextPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        GlassPrimaryButton(
          label: '重试',
          icon: Icons.refresh,
          semanticsLabel: '重新检测这张图片',
          onPressed: onPick,
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    required this.palette,
    this.mono = false,
  });

  final String label;
  final String value;
  final AppPalette palette;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: AppLayout.keyValueLabelWidth,
            child: Text(
              label,
              style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppType.footnote.copyWith(
                color: palette.glassTextPrimary,
                fontFamilyFallback: mono ? AppType.monoFallback : AppType.fontFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 玻璃卡内的扁平动作按钮（不作为第三块玻璃，避免超预算）
class _FlatButton extends StatelessWidget {
  const _FlatButton({
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AppLayout.secondaryButtonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: palette.glassRimOther),
            color: palette.glassOverlayWhite,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.footnote.copyWith(color: palette.glassTextPrimary),
          ),
        ),
      ),
    );
  }
}
