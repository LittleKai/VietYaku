import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/settings_layout.dart';
import 'settings_provider.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  static const _fontFamilies = <String>[
    '',
    'Segoe UI',
    'Yu Gothic UI',
    'Meiryo',
    'MS Gothic',
    'Microsoft YaHei',
    'SimSun',
    'Times New Roman',
  ];

  static List<({Color color, String label})> _katakanaOptions(bool isDark) => [
    (
      color: isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32),
      label: 'Xanh lục',
    ),
    (
      color: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF202124),
      label: isDark ? 'Trắng' : 'Đen',
    ),
    (
      color: isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
      label: 'Đỏ',
    ),
    (
      color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
      label: 'Xanh dương',
    ),
    (
      color: isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
      label: 'Cam',
    ),
    (
      color: isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A),
      label: 'Tím',
    ),
    (
      color: isDark ? const Color(0xFF4DD0E1) : const Color(0xFF00838F),
      label: 'Xanh ngọc',
    ),
    (
      color: isDark ? const Color(0xFFB0BEC5) : const Color(0xFF616161),
      label: 'Xám',
    ),
  ];

  void _openPaneFontDialog(BuildContext context) {
    showAppDialog<void>(
      context: context,
      icon: Icons.format_size,
      accentColor: const Color(0xFF1565C0),
      title: 'Cỡ chữ và font từng ô',
      description:
          'Điều chỉnh riêng cho từng vùng văn bản. Thay đổi được áp dụng ngay.',
      width: 780,
      content: Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          final notifier = ref.read(settingsProvider.notifier);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < PaneId.values.length; index++) ...[
                _PaneFontRow(
                  id: PaneId.values[index],
                  font: settings.paneFontFor(PaneId.values[index]),
                  fontFamilies: _fontFamilies,
                  onSizeChanged: (value) =>
                      notifier.setPaneFont(PaneId.values[index], size: value),
                  onFamilyChanged: (value) =>
                      notifier.setPaneFont(PaneId.values[index], family: value),
                ),
                if (index != PaneId.values.length - 1)
                  Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
              ],
            ],
          );
        },
      ),
      actionsBuilder: (dialogContext) => [
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Hoàn tất'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final katakanaOptions = _katakanaOptions(isDark);

    return SettingsPage(
      title: 'Giao diện',
      description:
          'Điều chỉnh cách văn bản và màu sắc được trình bày trong ứng dụng.',
      children: [
        SettingsSection(
          icon: Icons.contrast,
          accentColor: const Color(0xFF6A1B9A),
          title: 'Chủ đề giao diện',
          description:
              'Chuyển đổi giữa chế độ nền sáng, nền tối hoặc tự động theo hệ thống.',
          children: [
            SettingsControlRow(
              title: 'Chế độ hiển thị',
              description:
                  'Tùy chỉnh màu nền sáng/tối cho toàn bộ giao diện VietYaku.',
              controlWidth: 320,
              control: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Sáng'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Tối'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('Hệ thống'),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    notifier.setThemeMode(selection.first);
                  }
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          icon: Icons.format_size,
          accentColor: const Color(0xFF3949AB),
          title: 'Chữ giao diện',
          description:
              'Cỡ chữ và font cho toàn bộ giao diện: nút, nhãn, dialog, cài đặt… '
              'Không đổi cỡ chữ nội dung các ô dịch.',
          children: [
            _SystemFontRow(
              scale: settings.uiFontScale,
              family: settings.uiFontFamily,
              fontFamilies: _fontFamilies,
              onScaleChanged: notifier.setUiFontScale,
              onFamilyChanged: notifier.setUiFontFamily,
            ),
          ],
        ),
        SettingsSection(
          icon: Icons.text_fields,
          accentColor: const Color(0xFF1565C0),
          title: 'Chữ trong các ô',
          description: 'Mỗi vùng có thể dùng cỡ chữ và font riêng.',
          children: [
            SettingsControlRow(
              title: 'Cỡ chữ và font',
              description:
                  'Nguồn, Hán Việt, VietPhrase, Nghĩa và Bản dịch được chỉnh độc lập.',
              controlWidth: 260,
              control: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Chỉnh chữ từng ô'),
                  onPressed: () => _openPaneFontDialog(context),
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          icon: Icons.color_lens_outlined,
          accentColor: const Color(0xFF7B1FA2),
          title: 'Màu ký tự',
          description:
              'Màu dùng cho Katakana và Furigana chưa dịch trong VietPhrase.',
          children: [
            SettingsControlRow(
              title: 'Katakana và Furigana',
              description:
                  'Màu này chỉ áp dụng cho nội dung, không thay màu giao diện.',
              controlWidth: 390,
              control: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in katakanaOptions)
                    _ColorSwatch(
                      color: option.color,
                      label: option.label,
                      selected:
                          settings.katakanaColor == option.color.toARGB32() ||
                          (isDark &&
                              settings.katakanaColor ==
                                  const Color(0xFF2E7D32).toARGB32() &&
                              option.color == const Color(0xFF66BB6A)) ||
                          (isDark &&
                              settings.katakanaColor ==
                                  const Color(0xFF202124).toARGB32() &&
                              option.color == const Color(0xFFFFFFFF)),
                      onTap: () =>
                          notifier.setKatakanaColor(option.color.toARGB32()),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          icon: Icons.visibility_outlined,
          accentColor: const Color(0xFF00897B),
          title: 'Hiển thị bản dịch',
          description: 'Quy tắc trình bày VietPhrase đa nghĩa và dấu câu CJK.',
          children: [
            SettingsSwitchRow(
              title: 'Bọc ngoặc vuông khi chỉ có một nghĩa',
              description:
                  'Trong tab đa nghĩa, cụm một nghĩa vẫn được hiển thị trong [ ].',
              value: settings.bracketSingleMeaning,
              onChanged: notifier.setBracketSingleMeaning,
            ),
            SettingsSwitchRow(
              title: 'Giữ nguyên ngoặc CJK đặc biệt',
              description:
                  'Giữ 『』《》〈〉〝〟. Khi tắt, các dấu này được chuyển thành dấu ngoặc kép.',
              value: settings.keepSpecialQuotes,
              onChanged: notifier.setKeepSpecialQuotes,
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkColor = color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, color: checkColor, size: 20)
              : null,
        ),
      ),
    );
  }
}

/// Cỡ chữ + font cho toàn giao diện (chrome). Áp ngay khi kéo/chọn.
class _SystemFontRow extends StatelessWidget {
  const _SystemFontRow({
    required this.scale,
    required this.family,
    required this.fontFamilies,
    required this.onScaleChanged,
    required this.onFamilyChanged,
  });

  final double scale;
  final String family;
  final List<String> fontFamilies;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<String> onFamilyChanged;

  @override
  Widget build(BuildContext context) {
    final selected = fontFamilies.contains(family) ? family : '';
    final percent = (scale * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 610;
          final slider = Row(
            children: [
              Expanded(
                child: Slider(
                  value: scale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 12,
                  label: '$percent%',
                  onChanged: onScaleChanged,
                ),
              ),
              SettingsValueBadge(label: '$percent%', width: 56),
            ],
          );
          final dropdown = DropdownMenu<String>(
            key: ValueKey('ui:$selected'),
            initialSelection: selected,
            label: const Text('Font'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (value) => onFamilyChanged(value ?? ''),
            dropdownMenuEntries: [
              for (final item in fontFamilies)
                DropdownMenuEntry<String>(
                  value: item,
                  label: item.isEmpty ? 'Mặc định hệ thống' : item,
                  style: MenuItemButton.styleFrom(
                    textStyle: TextStyle(
                      fontFamily: item.isEmpty ? null : item,
                    ),
                  ),
                ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cỡ chữ', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              if (compact) ...[
                slider,
                const SizedBox(height: 12),
                dropdown,
              ] else
                Row(
                  children: [
                    Expanded(child: slider),
                    const SizedBox(width: 24),
                    SizedBox(width: 250, child: dropdown),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PaneFontRow extends StatelessWidget {
  const _PaneFontRow({
    required this.id,
    required this.font,
    required this.fontFamilies,
    required this.onSizeChanged,
    required this.onFamilyChanged,
  });

  final PaneId id;
  final PaneFont font;
  final List<String> fontFamilies;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<String> onFamilyChanged;

  @override
  Widget build(BuildContext context) {
    final family = fontFamilies.contains(font.family) ? font.family : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 610;
          final slider = Row(
            children: [
              Expanded(
                child: Slider(
                  value: font.size,
                  min: 10,
                  max: 28,
                  divisions: 18,
                  label: '${font.size.round()} px',
                  onChanged: onSizeChanged,
                ),
              ),
              SettingsValueBadge(label: '${font.size.round()}', width: 52),
            ],
          );
          final dropdown = DropdownMenu<String>(
            key: ValueKey('${id.name}:$family'),
            initialSelection: family,
            label: const Text('Font'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (value) => onFamilyChanged(value ?? ''),
            dropdownMenuEntries: [
              for (final item in fontFamilies)
                DropdownMenuEntry<String>(
                  value: item,
                  label: item.isEmpty ? 'Mặc định hệ thống' : item,
                  style: MenuItemButton.styleFrom(
                    textStyle: TextStyle(
                      fontFamily: item.isEmpty ? null : item,
                    ),
                  ),
                ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                paneLabels[id]!,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                slider,
                const SizedBox(height: 10),
                dropdown,
              ] else
                Row(
                  children: [
                    Expanded(child: slider),
                    const SizedBox(width: 24),
                    SizedBox(width: 250, child: dropdown),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
