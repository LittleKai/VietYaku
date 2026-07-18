import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../application/translation_controller.dart';
import '../domain/translation_engine.dart';
import 'han_viet_pane.dart';
import 'lacviet_panel.dart';
import 'result_pane.dart';
import 'source_pane.dart';

/// Bố cục kiểu QuickTranslator: trái-trên tabs [Nguồn | Hán Việt],
/// trái-dưới ô Nghĩa (LacViet), phải tabs VietPhrase.
class TranslateScreen extends ConsumerWidget {
  const TranslateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dicts = ref.watch(dictionariesProvider);

    return Column(
      children: [
        const _MenuBar(),
        const Divider(height: 1, thickness: 1),
        if (dicts.isLoading)
          const LinearProgressIndicator(minHeight: 3)
        else if (dicts.hasError)
          MaterialBanner(
            content: Text('Lỗi nạp từ điển: ${dicts.error}'),
            actions: [
              TextButton(
                onPressed: () => ref.invalidate(dictionariesProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        const Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(flex: 3, child: _SourceTabs()),
                    Divider(height: 1, thickness: 1),
                    Expanded(flex: 2, child: LacVietPanel()),
                  ],
                ),
              ),
              VerticalDivider(width: 1, thickness: 1),
              Expanded(flex: 3, child: ResultPane()),
            ],
          ),
        ),
      ],
    );
  }
}

/// Menu bar trên cùng: chọn ngôn ngữ Nhật/Trung + Dán & Dịch.
class _MenuBar extends ConsumerWidget {
  const _MenuBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(translationControllerProvider.select((s) => s.mode));
    final dictsLoading = ref.watch(dictionariesProvider).isLoading;
    final syncing = ref.watch(
      dictionarySyncProvider.select((s) => s.isSyncing),
    );

    Future<void> syncDictionary() async {
      try {
        await ref.read(dictionarySyncProvider.notifier).sync(mode);
      } catch (_) {
        // Controller đã ánh xạ lỗi kỹ thuật sang thông báo UI.
      }
      if (!context.mounted) return;
      final message = ref.read(dictionarySyncProvider).message;
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    }

    final syncIcon = syncing
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.sync, size: 17);
    final onSync = dictsLoading || syncing ? null : syncDictionary;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              SegmentedButton<TranslationMode>(
                segments: const [
                  ButtonSegment(
                    value: TranslationMode.japanese,
                    label: Text('Nhật', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: TranslationMode.chinese,
                    label: Text('Trung', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (selection) => ref
                    .read(translationControllerProvider.notifier)
                    .setMode(selection.first),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.translate, size: 16),
                label: const Text('Dịch', style: TextStyle(fontSize: 13)),
                onPressed: dictsLoading
                    ? null
                    : () => ref
                          .read(translationControllerProvider.notifier)
                          .translate(ref.read(sourceDraftProvider)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.paste, size: 16),
                label: const Text('Dán & Dịch', style: TextStyle(fontSize: 13)),
                onPressed: dictsLoading
                    ? null
                    : () => ref
                          .read(translationControllerProvider.notifier)
                          .pasteAndTranslate(),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              const Spacer(),
              if (constraints.maxWidth < 760)
                IconButton.outlined(
                  icon: syncIcon,
                  tooltip: 'Cập nhật từ điển',
                  onPressed: onSync,
                  visualDensity: VisualDensity.compact,
                )
              else
                OutlinedButton.icon(
                  icon: syncIcon,
                  label: const Text(
                    'Cập nhật từ điển',
                    style: TextStyle(fontSize: 13),
                  ),
                  onPressed: onSync,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tabs [Nguồn | Hán Việt] dùng IndexedStack để giữ state SourcePane
/// (text đang gõ, clipboard watcher) khi đổi tab. Hàng chọn ngôn ngữ
/// Nhật/Trung nằm TRÊN tabs.
class _SourceTabs extends ConsumerStatefulWidget {
  const _SourceTabs();

  @override
  ConsumerState<_SourceTabs> createState() => _SourceTabsState();
}

class _SourceTabsState extends ConsumerState<_SourceTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Nguồn'),
            Tab(text: 'Hán Việt'),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _tabController.index,
            children: const [SourcePane(), HanVietPane()],
          ),
        ),
      ],
    );
  }
}
