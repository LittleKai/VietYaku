import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/repair/presentation/repair_screen.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/settings_screen.dart';
import 'features/translation/presentation/translate_screen.dart';

class VietYakuApp extends StatelessWidget {
  const VietYakuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VietYaku',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

/// Dialog chỉnh cỡ chữ + font các ô Nguồn/Kết quả/Nghĩa (áp dụng ngay).
class _FontSettingsDialog extends ConsumerWidget {
  const _FontSettingsDialog();

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return AlertDialog(
      title: const Text('Cỡ chữ & font các ô'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cỡ chữ: ${settings.paneFontSize.round()}'),
            Slider(
              value: settings.paneFontSize,
              min: 10,
              max: 28,
              divisions: 18,
              label: '${settings.paneFontSize.round()}',
              onChanged: (v) => notifier.setPaneFontSize(v),
            ),
            const SizedBox(height: 8),
            const Text('Font chữ'),
            const SizedBox(height: 4),
            DropdownButton<String>(
              value: _fontFamilies.contains(settings.paneFontFamily)
                  ? settings.paneFontFamily
                  : '',
              isExpanded: true,
              items: [
                for (final f in _fontFamilies)
                  DropdownMenuItem(
                    value: f,
                    child: Text(f.isEmpty ? 'Mặc định hệ thống' : f,
                        style: TextStyle(
                            fontFamily: f.isEmpty ? null : f)),
                  ),
              ],
              onChanged: (v) => notifier.setPaneFontFamily(v ?? ''),
            ),
            const SizedBox(height: 12),
            Text(
              'あの日の夢を追いかけて 学校へ行く',
              style: settings.paneTextStyle(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  bool _isExtended = false; // Mặc định ẩn bớt

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: _isExtended,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            labelType: _isExtended ? null : NavigationRailLabelType.none,
            leading: Column(
              children: [
                const SizedBox(height: 8),
                IconButton(
                  icon: Icon(_isExtended ? Icons.menu_open : Icons.menu),
                  tooltip: _isExtended ? 'Thu nhỏ menu' : 'Mở rộng menu',
                  onPressed: () => setState(() => _isExtended = !_isExtended),
                ),
                const SizedBox(height: 8),
              ],
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: IconButton(
                icon: const Icon(Icons.text_fields),
                tooltip: 'Cỡ chữ & font các ô',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _FontSettingsDialog(),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.translate),
                selectedIcon: Icon(Icons.translate, color: Colors.indigo),
                label: Text('Dịch'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.build),
                selectedIcon: Icon(Icons.build, color: Colors.indigo),
                label: Text('Sửa từ điển'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                selectedIcon: Icon(Icons.settings, color: Colors.indigo),
                label: Text('Cài đặt'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                TranslateScreen(),
                RepairScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
