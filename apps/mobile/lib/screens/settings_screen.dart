// 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
//
// 设置（规范 §4.6 + §7.2 + §8）：API 地址、玻璃档位、外观、隐私说明。
//
// 玻璃预算（≤ 3）：① 顶部标题胶囊 ② 设置卡 ③ 悬浮 TabBar。
// 卡内的输入框/选项用不透明面（玻璃内不再叠玻璃）。

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/glass_container.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrl;

  @override
  void initState() {
    super.initState();
    // read() 不建立依赖，可在 initState 使用
    _baseUrl = TextEditingController(text: AppStateScope.read(context).apiBaseUrl);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: AppMotion.toast),
    );
  }

  Future<void> _saveBaseUrl() async {
    final AppState state = AppStateScope.read(context);
    final bool ok = state.applyBaseUrl(_baseUrl.text);
    if (!ok) {
      _toast('API 地址不合法，示例：http://192.168.1.10:8000');
      return;
    }
    setState(() {});
    final String? error = await state.testConnection();
    if (!mounted) {
      return;
    }
    _toast(error == null
        ? '已保存，服务连接正常（本月 ${state.quotaUsed}/${state.quotaLimit}）'
        : '已保存，但连接失败：$error');
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final AppPalette palette = AppPalette.of(context);
    final MediaQueryData? media = MediaQuery.maybeOf(context);

    // 生效档位：设置项 + 系统无障碍（降低透明度/高对比）+ 省电模式
    final GlassTier effectiveTier = state.resolveTier(
      reduceTransparency: media?.highContrast ?? false,
      powerSaver: false, // TODO(M3): 读取省电模式（battery_plus / 平台通道）
      grade: DeviceGrade.unknown,
      measuredFps: null,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppLayout.scrollBottomInset,
      ),
      children: <Widget>[
        const _TitlePill(),
        const SizedBox(height: AppSpacing.xl),
        GlassContainer(
          radius: AppRadius.lg,
          padding: const EdgeInsets.all(AppSpacing.glassInner),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── 运行模式 ─────────────────────────────
              Text(
                '运行模式',
                style: AppType.title2.copyWith(color: palette.glassTextPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                state.offlineMode
                    ? '本地离线：嵌入/提取在手机本机完成，不联网、不上传图片'
                    : '服务端模式：图片上传到你配置的 InvisMark 服务端处理',
                style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '本地离线模式',
                      style: AppType.footnote.copyWith(color: palette.textPrimary),
                    ),
                  ),
                  Switch(
                    value: state.offlineMode,
                    activeColor: AppBrand.ctaEnd,
                    onChanged: (bool value) =>
                        AppStateScope.read(context).setOfflineMode(value),
                  ),
                ],
              ),
              if (state.offlineMode) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '首次使用会生成一个本地种子（存本机），换机或清数据后旧图将无法用本机提取。',
                  style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                ),
              ] else ...<Widget>[
                _SectionDivider(palette: palette),
                // ── API 地址（仅服务端模式需要）────────────
                Text(
                  'API 地址',
                  style: AppType.title2.copyWith(color: palette.glassTextPrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Android 模拟器用 10.0.2.2 访问宿主机；真机填局域网 IP',
                  style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      // 输入框用不透明面：玻璃上再叠模糊会把文字边缘糊掉
                      child: TextField(
                        controller: _baseUrl,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        style: AppType.footnote.copyWith(color: palette.textPrimary),
                        cursorColor: AppBrand.ctaEnd,
                        decoration: InputDecoration(
                          hintText: 'http://192.168.1.10:8000',
                          isDense: true,
                        ),
                        onSubmitted: (String _) => _saveBaseUrl(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: _saveBaseUrl,
                      child: Text(
                        '保存并测试',
                        style: AppType.footnote.copyWith(color: AppBrand.ctaEnd),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '本月用量：${state.quotaUsed} / ${state.quotaLimit}'
                  '（服务端未启动时显示 0，可在电脑上跑 python -m invismark serve --host 0.0.0.0）',
                  style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                ),
              ],
              _SectionDivider(palette: palette),
              _SectionDivider(palette: palette),

              // ── 视觉效果（三档降级）─────────────────────
              Text(
                '视觉效果',
                style: AppType.title2.copyWith(color: palette.glassTextPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '当前生效：${_tierLabel(effectiveTier)}',
                style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              _ChipRow<GlassPreference>(
                values: GlassPreference.values,
                selected: state.glassPreference,
                labelOf: _preferenceLabel,
                palette: palette,
                onSelected: (GlassPreference value) =>
                    AppStateScope.read(context).setGlassPreference(value),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final List<String> row in _tierNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text.rich(
                    TextSpan(
                      children: <TextSpan>[
                        TextSpan(
                          text: '${row[0]}：',
                          style: AppType.footnote.copyWith(color: palette.glassTextPrimary),
                        ),
                        TextSpan(text: row[1]),
                      ],
                    ),
                    style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                  ),
                ),
              _SectionDivider(palette: palette),

              // ── 外观 ────────────────────────────────
              Text(
                '外观',
                style: AppType.title2.copyWith(color: palette.glassTextPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              _ChipRow<ThemePreference>(
                values: ThemePreference.values,
                selected: state.themePreference,
                labelOf: (ThemePreference value) => switch (value) {
                  ThemePreference.system => '跟随系统',
                  ThemePreference.light => '浅色',
                  ThemePreference.dark => '深色',
                },
                palette: palette,
                onSelected: (ThemePreference value) =>
                    AppStateScope.read(context).setThemePreference(value),
              ),
              _SectionDivider(palette: palette),

              // ── 隐私说明 ────────────────────────────
              Text(
                '隐私说明',
                style: AppType.title2.copyWith(color: palette.glassTextPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final String line in _privacyNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.lock_outline,
                        size: AppIconSize.sm,
                        color: palette.glassTextSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          line,
                          style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              _SectionDivider(palette: palette),
              Text(
                '隐迹 InvisMark · 移动端 v0.1.0\nUI 规范 v0.1 · Apache-2.0',
                style: AppType.footnote.copyWith(color: palette.glassTextSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const List<List<String>> _tierNotes = <List<String>>[
    <String>['自动', '按 200ms 帧率采样与设备分级在 完整/精简/关闭 间切换'],
    <String>['完整', 'blur 24 + 焦点边缘光；每屏仅 1 块焦点玻璃'],
    <String>['精简', 'blur 12，关闭实时高光扫过动画'],
    <String>['关闭', '不使用 BackdropFilter，改半透明纯色卡片，保留圆角与层级'],
  ];

  static const List<String> _privacyNotes = <String>[
    '水印内不存明文用户信息：只写入 24 字节 trace_id，用户信息通过服务端映射表反查。',
    '图片只用于本次嵌入 / 提取，不进入任何样张集或训练数据。',
    '分享前会提示渠道风险：二次压缩可能降低检出率，本产品不承诺"保证可检出"。',
  ];

  static String _preferenceLabel(GlassPreference value) => switch (value) {
        GlassPreference.auto => '自动',
        GlassPreference.full => '完整',
        GlassPreference.lite => '精简',
        GlassPreference.opaque => '关闭',
      };

  static String _tierLabel(GlassTier tier) => switch (tier) {
        GlassTier.full => '完整 (Full)',
        GlassTier.lite => '精简 (Lite)',
        GlassTier.opaque => '关闭 (Opaque)',
      };
}

/// ① 标题胶囊（本屏第 1 块玻璃）
class _TitlePill extends StatelessWidget {
  const _TitlePill();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return GlassContainer(
      radius: AppRadius.full,
      padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.xl),
      child: SizedBox(
        height: AppLayout.navPillHeight,
        child: Row(
          children: <Widget>[
            Icon(Icons.tune, size: AppIconSize.sm, color: palette.glassTextPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '设置',
              style: AppType.headline.copyWith(color: palette.glassTextPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Divider(height: 1, color: palette.glassRimOther),
    );
  }
}

/// 不透明选项 chip（玻璃内不叠玻璃）
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.palette,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final AppPalette palette;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final T value in values)
          Semantics(
            button: true,
            selected: value == selected,
            label: labelOf(value),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(value),
              child: Container(
                constraints: const BoxConstraints(minHeight: AppLayout.minTouchTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == selected ? palette.chipSelected : palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: value == selected ? AppBrand.ctaEnd : palette.border,
                  ),
                ),
                child: Text(
                  labelOf(value),
                  style: AppType.footnote.copyWith(
                    color: value == selected ? AppBrand.ctaEnd : palette.textSecondary,
                    fontWeight: value == selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
