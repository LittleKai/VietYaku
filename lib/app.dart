import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'features/dictionary_sync/application/dictionary_sync_controller.dart';
import 'features/epub_converter/presentation/epub_converter_screen.dart';
import 'features/settings/appearance_screen.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/settings_screen.dart';
import 'features/translation/domain/translation_engine.dart';
import 'features/translation/presentation/translate_screen.dart';
import 'features/update/application/update_controller.dart';
import 'features/update/presentation/update_dialog.dart';

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

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;
  bool _isExtended = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      if (settings.autoCheckUpdates) {
        ref
            .read(updateControllerProvider.notifier)
            .checkForUpdate(silent: true);
      }
      if (settings.autoSyncDictionary) {
        // Kéo tuần tự cả hai ngôn ngữ (sync() chặn chạy song song).
        () async {
          final notifier = ref.read(dictionarySyncProvider.notifier);
          for (final mode in TranslationMode.values) {
            try {
              await notifier.sync(mode);
            } catch (_) {
              // Lỗi mạng đã vào state.message; bỏ qua, kéo ngôn ngữ tiếp theo.
            }
          }
        }();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateControllerProvider.select((s) => s.phase), (
      previous,
      next,
    ) {
      if (next == UpdatePhase.available) {
        maybeShowUpdateDialog(context, ref);
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final canExtend = constraints.maxWidth >= 920;
        final extended = canExtend && _isExtended;
        final disableAnimations = MediaQuery.disableAnimationsOf(context);

        return Scaffold(
          body: Row(
            children: [
              AnimatedContainer(
                duration: disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: NavigationRail(
                  extended: extended,
                  minWidth: 76,
                  minExtendedWidth: 224,
                  groupAlignment: -1,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  labelType: extended ? null : NavigationRailLabelType.none,
                  leading: _SidebarHeader(
                    extended: extended,
                    canExtend: canExtend,
                    onToggle: () => setState(() => _isExtended = !_isExtended),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: _NavIcon(
                        icon: Icons.translate_outlined,
                        color: Color(0xFF1565C0),
                      ),
                      selectedIcon: _NavIcon(
                        icon: Icons.translate,
                        color: Color(0xFF1565C0),
                        selected: true,
                      ),
                      label: Text('Dịch'),
                      padding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    NavigationRailDestination(
                      icon: _NavIcon(
                        icon: Icons.palette_outlined,
                        color: Color(0xFF7B1FA2),
                      ),
                      selectedIcon: _NavIcon(
                        icon: Icons.palette,
                        color: Color(0xFF7B1FA2),
                        selected: true,
                      ),
                      label: Text('Giao diện'),
                      padding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    NavigationRailDestination(
                      icon: _NavIcon(
                        icon: Icons.settings_outlined,
                        color: Color(0xFFEF6C00),
                      ),
                      selectedIcon: _NavIcon(
                        icon: Icons.settings,
                        color: Color(0xFFEF6C00),
                        selected: true,
                      ),
                      label: Text('Cài đặt'),
                      padding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    NavigationRailDestination(
                      icon: _NavIcon(
                        icon: Icons.auto_stories_outlined,
                        color: Color(0xFF00897B),
                      ),
                      selectedIcon: _NavIcon(
                        icon: Icons.auto_stories,
                        color: Color(0xFF00897B),
                        selected: true,
                      ),
                      label: Text('EPUB'),
                      padding: EdgeInsets.symmetric(vertical: 4),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: const [
                    TranslateScreen(),
                    AppearanceScreen(),
                    SettingsScreen(),
                    EpubConverterScreen(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.color,
    this.selected = false,
  });

  final IconData icon;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final resolved = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, 0.32)!
        : color;
    return Icon(
      icon,
      color: resolved.withValues(alpha: selected ? 1 : 0.82),
      size: selected ? 25 : 24,
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.extended,
    required this.canExtend,
    required this.onToggle,
  });

  final bool extended;
  final bool canExtend;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final brand = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: 36,
        height: 36,
        filterQuality: FilterQuality.high,
      ),
    );

    if (!extended) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        child: Column(
          children: [
            brand,
            if (canExtend) ...[
              const SizedBox(height: 10),
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Mở rộng thanh bên',
                onPressed: onToggle,
              ),
            ],
          ],
        ),
      );
    }

    return FutureBuilder<List<String>>(
      future: Future.wait([
        PackageInfo.fromPlatform().then((info) => info.version),
        windowManager.getTitle(),
      ]),
      builder: (context, snapshot) {
        final version = snapshot.data?[0] ?? '';
        final windowTitle = snapshot.data?[1] ?? 'VietYaku';
        return SizedBox(
          width: 224,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 20),
            child: Row(
              children: [
                brand,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        windowTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'v$version',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.menu_open),
                  tooltip: 'Thu gọn thanh bên',
                  onPressed: onToggle,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
