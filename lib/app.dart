import 'dart:io';

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

class VietYakuApp extends ConsumerWidget {
  const VietYakuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontFamily = ref.watch(
      settingsProvider.select((s) => s.uiFontFamily),
    );
    final fontScale = ref.watch(settingsProvider.select((s) => s.uiFontScale));
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: 'VietYaku v1.0.5',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(fontFamily: fontFamily, fontScale: fontScale),
      darkTheme: AppTheme.dark(fontFamily: fontFamily, fontScale: fontScale),
      themeMode: themeMode,
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
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        windowManager.isMaximized().then((maximized) {
          if (!maximized) {
            windowManager.maximize();
          }
        });
        PackageInfo.fromPlatform().then((info) {
          windowManager.setTitle('VietYaku v${info.version}');
        }).catchError((_) {});
      }
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
          body: Stack(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    child: NavigationRail(
                      extended: extended,
                      minWidth: 76,
                      minExtendedWidth: 224,
                      groupAlignment: -1,
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: (index) =>
                          setState(() => _selectedIndex = index),
                      labelType: extended ? null : NavigationRailLabelType.none,
                      leading: _SidebarHeader(extended: extended),
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
              if (canExtend)
                AnimatedPositioned(
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  left: (extended ? 224 : 76) - 12,
                  top: 56,
                  child: _SidebarToggleButton(
                    extended: extended,
                    onPressed: () => setState(() => _isExtended = !_isExtended),
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
  const _SidebarHeader({required this.extended});

  final bool extended;

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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: brand,
      );
    }

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '';
        return SizedBox(
          width: 224,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                        'VietYaku',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (version.isNotEmpty)
                        Text(
                          'v$version',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarToggleButton extends StatefulWidget {
  const _SidebarToggleButton({required this.extended, required this.onPressed});

  final bool extended;
  final VoidCallback onPressed;

  @override
  State<_SidebarToggleButton> createState() => _SidebarToggleButtonState();
}

class _SidebarToggleButtonState extends State<_SidebarToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHovered
                ? colorScheme.primaryContainer
                : colorScheme.surface,
            border: Border.all(
              color: _isHovered
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isHovered ? 0.12 : 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            widget.extended ? Icons.chevron_left : Icons.chevron_right,
            size: 16,
            color: _isHovered
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
