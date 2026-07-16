import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
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

/// Tabs [Nguồn | Hán Việt] dùng IndexedStack để giữ state SourcePane
/// (text đang gõ, clipboard watcher) khi đổi tab.
class _SourceTabs extends StatefulWidget {
  const _SourceTabs();

  @override
  State<_SourceTabs> createState() => _SourceTabsState();
}

class _SourceTabsState extends State<_SourceTabs>
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
          tabs: const [Tab(text: 'Nguồn'), Tab(text: 'Hán Việt')],
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
