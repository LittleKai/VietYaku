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

  static const _katakanaColors = <({Color color, String label})>[
    (color: Color(0xFF2E7D32), label: 'Xanh lục'),
    (color: Color(0xFF202124), label: 'Đen'),
    (color: Color(0xFFC62828), label: 'Đỏ'),
    (color: Color(0xFF1565C0), label: 'Xanh dương'),
    (color: Color(0xFFE65100), label: 'Cam'),
    (color: Color(0xFF6A1B9A), label: 'Tím'),
    (color: Color(0xFF00838F), label: 'Xanh ngọc'),
    (color: Color(0xFF616161), label: 'Xám'),
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

    return SettingsPage(
      title: 'Giao diện',
      description:
          'Điều chỉnh cách văn bản được trình bày trong không gian dịch.',
      children: [
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
                  for (final option in _katakanaColors)
                    _ColorSwatch(
                      color: option.color,
                      label: option.label,
                      selected:
                          settings.katakanaColor == option.color.toARGB32(),
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
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
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
    final scheme = Theme.of(context).colorScheme;
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
              Container(
                width: 52,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${font.size.round()}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
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
