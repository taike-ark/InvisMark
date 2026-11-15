// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 分享渠道风险提示（规范 §4.4）：点"分享"必须先弹玻璃 sheet 列出渠道风险；
// 文案不得出现"保证可检出"之类承诺（§9 验收清单）。

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass_button.dart';
import 'glass_container.dart';

/// 单个分享渠道的风险描述。
class ShareChannelRisk {
  const ShareChannelRisk({required this.channel, required this.note, required this.safe});

  final String channel;
  final String note;

  /// true 表示该渠道基本保真（原图直发），false 表示会二次压缩。
  final bool safe;
}

abstract final class ShareChannelRisks {
  static const List<ShareChannelRisk> all = <ShareChannelRisk>[
    ShareChannelRisk(
      channel: '微信好友 · 原图',
      note: '以"原图"发送时基本保持原始像素，检出率较高',
      safe: true,
    ),
    ShareChannelRisk(
      channel: '微信聊天 · 普通图片',
      note: '会压制重编码，检出率可能下降',
      safe: false,
    ),
    ShareChannelRisk(
      channel: '朋友圈 / 抖音 / 小红书',
      note: '二次压缩 + 缩放，检出率明显下降',
      safe: false,
    ),
    ShareChannelRisk(
      channel: '截图 / 屏幕翻拍转发',
      note: '取决于屏幕分辨率与缩放比例，可能无法检出',
      safe: false,
    ),
  ];
}

/// 内联风险提示条（玻璃 md 圆角，琥珀着色）。放在结果页指标行下方。
class RiskBanner extends StatelessWidget {
  const RiskBanner({
    super.key,
    this.text = '分享渠道风险：朋友圈 / 抖音会二次压缩，检出率会下降；微信"原图"相对更安全。',
    this.onTap,
  });

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return GlassContainer(
      radius: AppRadius.md,
      tint: AppBrand.warn,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      onTap: onTap,
      semanticsLabel: '分享渠道风险提示',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: AppIconSize.sm, color: AppBrand.warn),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹出分享风险 sheet。返回 true 表示用户确认继续分享。
Future<bool> showShareRiskSheet(BuildContext context) async {
  final bool? confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppBrand.clear,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => const _ShareRiskSheet(),
  );
  return confirmed ?? false;
}

class _ShareRiskSheet extends StatelessWidget {
  const _ShareRiskSheet();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double bottomInset = MediaQuery.maybeOf(context)?.viewPadding.bottom ?? 0;

    // 该 sheet 是临时浮层，不计入"每屏 ≤ 3 块常驻玻璃"的预算
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
              Row(
                children: <Widget>[
                  const Icon(Icons.ios_share, size: AppIconSize.md, color: AppBrand.warn),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '分享前请确认渠道',
                      style: AppType.title2.copyWith(color: palette.glassTextPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final ShareChannelRisk risk in ShareChannelRisks.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        risk.safe ? Icons.check_circle_outline : Icons.error_outline,
                        size: AppIconSize.sm,
                        color: risk.safe ? AppBrand.ctaStart : AppBrand.warn,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: <TextSpan>[
                              TextSpan(
                                text: '${risk.channel}：',
                                style: AppType.footnote.copyWith(color: palette.glassTextPrimary),
                              ),
                              TextSpan(text: risk.note),
                            ],
                          ),
                          style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '水印无法保证在所有平台都被检出；保留原图与 trace_id 才是可靠的证据链。',
                style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              GlassPrimaryButton(
                label: '继续分享',
                icon: Icons.ios_share,
                semanticsLabel: '确认风险并继续分享图片',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassSecondaryButton(
                label: '先不分享',
                semanticsLabel: '取消分享',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
