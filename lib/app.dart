import 'package:flutter/material.dart';

import 'features/repair/presentation/repair_screen.dart';
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.translate),
                label: Text('Dịch'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.build),
                label: Text('Sửa từ điển'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
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
