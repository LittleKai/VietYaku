import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_provider.dart';
import '../application/lookup_controller.dart';
import '../application/translation_controller.dart';
import '../domain/token.dart';
import '../domain/translation_engine.dart';
import 'token_text_view.dart';

/// Kết quả dịch: tabs [VietPhrase một nghĩa | VietPhrase (đa nghĩa)] trên
/// cùng một token list — đổi tab chỉ đổi cách hiển thị, không dịch lại.
class ResultPane extends ConsumerStatefulWidget {
  const ResultPane({super.key});

  @override
  ConsumerState<ResultPane> createState() => _ResultPaneState();
}

class _ResultPaneState extends ConsumerState<ResultPane>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late final TextEditingController _vietController;

  // Tab Google Dịch (tạo khi bấm nút, dịch cả đoạn nguồn online).
  bool _gtTabOpen = false;
  bool _gtLoading = false;
  String? _gtText;

  bool get _multiMeaning => _tabController.index == 1;
  bool get _gtTabActive => _gtTabOpen && _tabController.index == 2;

  @override
  void initState() {
    super.initState();
    // Đa nghĩa là tab mặc định.
    _tabController = _makeController(length: 2, initialIndex: 1);
    _vietController = TextEditingController();
  }

  TabController _makeController({
    required int length,
    required int initialIndex,
  }) {
    final c = TabController(
      length: length,
      vsync: this,
      initialIndex: initialIndex,
    );
    c.addListener(() {
      if (!c.indexIsChanging) setState(() {});
    });
    return c;
  }

  Future<void> _openGoogleTranslateTab() async {
    if (!_gtTabOpen) {
      final old = _tabController;
      setState(() {
        _gtTabOpen = true;
        _tabController = _makeController(length: 3, initialIndex: 2);
      });
      old.dispose();
    } else {
      _tabController.animateTo(2);
    }
    await _fetchGoogleTranslate();
  }

  Future<void> _fetchGoogleTranslate() async {
    final state = ref.read(translationControllerProvider);
    if (state.sourceText.isEmpty || _gtLoading) return;
    setState(() {
      _gtLoading = true;
      _gtText = null;
    });
    final text = await ref
        .read(googleTranslateProvider)
        .translate(
          state.sourceText,
          sourceLang: state.mode == TranslationMode.japanese ? 'ja' : 'zh-CN',
        );
    if (!mounted) return;
    setState(() {
      _gtLoading = false;
      _gtText = text;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _vietController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translationControllerProvider);
    final String Function(Token) textOf = _multiMeaning
        ? (t) => t.displayAll
        : (t) => t.display;

    // Lắng nghe thay đổi của tokens để tự động điền gợi ý bản dịch thô vào ô Việt
    ref.listen(translationControllerProvider.select((s) => s.tokens), (
      previous,
      next,
    ) {
      if (next.isNotEmpty) {
        final plain = TokenTextView.plainText(next, (t) => t.display);
        _vietController.text = plain;
      } else {
        _vietController.clear();
      }
    });

    // Đổi đoạn nguồn khi tab Google Dịch đang mở → dịch lại online.
    ref.listen(translationControllerProvider.select((s) => s.sourceText), (
      previous,
      next,
    ) {
      if (_gtTabOpen && next.isNotEmpty) _fetchGoogleTranslate();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabController,
                tabs: [
                  const Tab(text: 'VietPhrase một nghĩa'),
                  const Tab(text: 'VietPhrase (đa nghĩa)'),
                  if (_gtTabOpen) const Tab(text: 'Google Dịch'),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.g_translate, size: 20),
              tooltip: 'Dịch cả đoạn bằng Google Translate (tab mới)',
              onPressed: state.hasResult ? _openGoogleTranslateTab : null,
            ),
          ],
        ),
        if (_gtTabActive)
          Expanded(child: _buildGoogleTranslateView(context))
        else if (!state.hasResult)
          const Expanded(
            child: Center(child: Text('Kết quả dịch sẽ hiện ở đây')),
          )
        else ...[
          // Phần 1: Vietphrase (chiếm flex 3)
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                        tooltip: 'Copy VietPhrase',
                        onPressed: () {
                          final text = TokenTextView.plainText(
                            state.tokens,
                            textOf,
                          );
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã copy VietPhrase'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TokenTextView(
                    tokens: state.tokens,
                    textOf: textOf,
                    paneId: PaneId.vietPhrase,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          // Phần 2: Ô Việt (chiếm flex 2)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.edit_note,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bản dịch Việt',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copy bản dịch Việt',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _vietController.text),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã copy bản dịch Việt'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.restart_alt, size: 18),
                        tooltip: 'Đặt lại theo VietPhrase',
                        onPressed: () {
                          final plain = TokenTextView.plainText(
                            state.tokens,
                            (t) => t.display,
                          );
                          setState(() => _vietController.text = plain);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: TextField(
                      controller: _vietController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: ref.watch(
                        settingsProvider.select(
                          (s) => s.paneTextStyleFor(PaneId.viet),
                        ),
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Nhập hoặc chỉnh sửa bản dịch thuần Việt tại đây...',
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGoogleTranslateView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Text(
                'Google Translate (online)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Dịch lại',
                onPressed: _gtLoading ? null : _fetchGoogleTranslate,
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy bản dịch Google',
                onPressed: _gtText == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _gtText!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã copy bản dịch Google'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: _gtLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _gtText ??
                        'Không lấy được bản dịch (mạng hoặc Google chặn). '
                            'Bấm Dịch lại để thử.',
                    style: ref.watch(
                      settingsProvider.select(
                        (s) => s.paneTextStyleFor(PaneId.viet),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
