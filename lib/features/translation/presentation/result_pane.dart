import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/translation_controller.dart';
import '../domain/token.dart';
import 'token_text_view.dart';

/// Kết quả dịch: tabs [VietPhrase một nghĩa | VietPhrase (đa nghĩa)] trên
/// cùng một token list — đổi tab chỉ đổi cách hiển thị, không dịch lại.
class ResultPane extends ConsumerStatefulWidget {
  const ResultPane({super.key});

  @override
  ConsumerState<ResultPane> createState() => _ResultPaneState();
}

class _ResultPaneState extends ConsumerState<ResultPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool get _multiMeaning => _tabController.index == 1;

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
    final state = ref.watch(translationControllerProvider);
    final String Function(Token) textOf =
        _multiMeaning ? (t) => t.displayAll : (t) => t.display;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'VietPhrase một nghĩa'),
            Tab(text: 'VietPhrase (đa nghĩa)'),
          ],
        ),
        if (!state.hasResult)
          const Expanded(
              child: Center(child: Text('Kết quả dịch sẽ hiện ở đây')))
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Text(
                  '${state.tokens.length} token · ${state.elapsedMs}ms',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy kết quả dịch',
                  onPressed: () {
                    final text =
                        TokenTextView.plainText(state.tokens, textOf);
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Đã copy kết quả'),
                      duration: Duration(seconds: 1),
                    ));
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TokenTextView(tokens: state.tokens, textOf: textOf),
          ),
        ],
      ],
    );
  }
}
