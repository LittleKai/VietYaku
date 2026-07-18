import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/settings/settings_screen.dart';
import 'features/translation/presentation/translate_screen.dart';

class VietYakuApp extends StatelessWidget {
  const VietYakuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VietYaku',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      // Tắt cây semantics app-wide: né bug engine Flutter Windows
      // (accessibility_bridge.cc "Failed to update ui::AXTree" → app crash khi
      // Windows AT poll semantics). Đánh đổi: không hỗ trợ screen-reader —
      // chấp nhận được cho công cụ desktop cá nhân. Chọn/copy text vẫn chạy.
      builder: (context, child) =>
          ExcludeSemantics(child: child ?? const SizedBox.shrink()),
      home: const HomeShell(),
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
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.translate_outlined),
                selectedIcon: Icon(Icons.translate),
                label: Text('Dịch'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
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
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
