import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  static const _katakanaColors = <Color>[
    Color(0xFF2E7D32), // xanh lục
    Color(0xFF000000), // đen
    Color(0xFFC62828), // đỏ
    Color(0xFF1565C0), // xanh dương
    Color(0xFFE65100), // cam
    Color(0xFF6A1B9A), // tím
    Color(0xFF00838F), // cyan
    Color(0xFF616161), // xám
  ];

  // Màu cho tiêu đề từng nhóm cài đặt.
  static const _titleColors = <Color>[
    Color(0xFF1565C0), // xanh dương
    Color(0xFF2E7D32), // xanh lá
    Color(0xFF6A1B9A), // tím
    Color(0xFFC62828), // đỏ
    Color(0xFFE65100), // cam
    Color(0xFF00838F), // cyan
  ];

  Widget _sectionTitle(BuildContext context, String text, int index) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      color: _titleColors[index % _titleColors.length],
      fontWeight: FontWeight.bold,
    ),
  );

  /// Dialog tuỳ chỉnh cỡ chữ & font cho từng ô.
  void _openPaneFontDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cỡ chữ & font từng ô'),
        content: SizedBox(
          width: 420,
          child: Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(settingsProvider);
              final notifier = ref.read(settingsProvider.notifier);
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final id in PaneId.values)
                      _PaneFontRow(
                        id: id,
                        font: settings.paneFontFor(id),
                        fontFamilies: _fontFamilies,
                        onSizeChanged: (value) =>
                            notifier.setPaneFont(id, size: value),
                        onFamilyChanged: (value) =>
                            notifier.setPaneFont(id, family: value),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(context, 'Cỡ chữ & font các ô', 0),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.text_fields),
            label: const Text('Tuỳ chỉnh cỡ chữ & font từng ô…'),
            onPressed: () => _openPaneFontDialog(context),
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Màu chữ Katakana/Furigana', 1),
        const SizedBox(height: 4),
        Text(
          'Màu cho kana (katakana/furigana) chưa dịch trong ô VietPhrase.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in _katakanaColors)
              _ColorSwatch(
                color: color,
                selected: settings.katakanaColor == color.toARGB32(),
                onTap: () => notifier.setKatakanaColor(color.toARGB32()),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Hiển thị', 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bọc [ ] cả cụm chỉ có 1 nghĩa'),
          subtitle: const Text(
            'Tab đa nghĩa: cụm có trong từ điển nhưng chỉ có 1 biến thể '
            'vẫn nằm trong ngoặc vuông.',
          ),
          value: settings.bracketSingleMeaning,
          onChanged: (v) => notifier.setBracketSingleMeaning(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Giữ nguyên ngoặc 『』《》〈〉〝〟'),
          subtitle: const Text(
            'Tắt để chuyển các ngoặc kép CJK đặc biệt thành dấu ". '
            '(「」 luôn chuyển thành ".)',
          ),
          value: settings.keepSpecialQuotes,
          onChanged: (v) => notifier.setKeepSpecialQuotes(v),
        ),
      ],
    );
  }
}

/// Ô màu chọn được cho màu chữ katakana/furigana.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(paneLabels[id]!)),
          Expanded(
            child: Slider(
              value: font.size,
              min: 10,
              max: 28,
              divisions: 18,
              label: '${font.size.round()}',
              onChanged: onSizeChanged,
            ),
          ),
          SizedBox(width: 34, child: Text('${font.size.round()}')),
          const SizedBox(width: 8),
          DropdownMenu<String>(
            key: ValueKey('${id.name}:${font.family}'),
            width: 220,
            initialSelection: fontFamilies.contains(font.family)
                ? font.family
                : '',
            label: const Text('Font'),
            onSelected: (value) => onFamilyChanged(value ?? ''),
            dropdownMenuEntries: [
              for (final family in fontFamilies)
                DropdownMenuEntry<String>(
                  value: family,
                  label: family.isEmpty ? 'Mặc định hệ thống' : family,
                  style: MenuItemButton.styleFrom(
                    textStyle: TextStyle(
                      fontFamily: family.isEmpty ? null : family,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
