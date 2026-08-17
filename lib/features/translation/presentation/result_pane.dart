import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/feature_help_button.dart';
import '../../clipboard/application/clipboard_reader_controller.dart';
import '../../settings/settings_provider.dart';
import '../application/lookup_controller.dart';
import '../application/translation_controller.dart';
import '../application/translation_rules_provider.dart';
import '../domain/token.dart';
import '../domain/translation_engine.dart';
import '../domain/translation_rule.dart';
import 'token_text_view.dart';

enum _ResultTabType {
  singleMeaning('VietPhrase một nghĩa'),
  multiMeaning('VietPhrase (đa nghĩa)'),
  postProcessing('Hậu xử lý'),
  googleTranslate('Google Dịch');

  final String label;
  const _ResultTabType(this.label);
}

/// Kết quả dịch: một nghĩa, đa nghĩa, hậu xử lý và Google Dịch tùy chọn.
class ResultPane extends ConsumerStatefulWidget {
  const ResultPane({super.key});

  @override
  ConsumerState<ResultPane> createState() => _ResultPaneState();
}

class _ResultPaneState extends ConsumerState<ResultPane>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Tab Google Dịch (tạo khi bấm nút, dịch cả đoạn nguồn online).
  bool _gtTabOpen = false;
  bool _gtLoading = false;
  String? _gtText;

  @override
  void initState() {
    super.initState();
    final postEnabled = ref.read(settingsProvider).postProcessingEnabled;
    final initialLength = 2 + (postEnabled ? 1 : 0);
    // Đa nghĩa là tab mặc định (index 1).
    _tabController = _makeController(length: initialLength, initialIndex: 1);
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
    final postEnabled = ref.read(settingsProvider).postProcessingEnabled;
    final activeTabs = <_ResultTabType>[
      _ResultTabType.singleMeaning,
      _ResultTabType.multiMeaning,
      if (postEnabled) _ResultTabType.postProcessing,
      _ResultTabType.googleTranslate,
    ];
    final gtIndex = activeTabs.indexOf(_ResultTabType.googleTranslate);

    if (!_gtTabOpen) {
      final old = _tabController;
      setState(() {
        _gtTabOpen = true;
        _tabController = _makeController(
          length: activeTabs.length,
          initialIndex: gtIndex,
        );
      });
      old.dispose();
    } else {
      _tabController.animateTo(gtIndex);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translationControllerProvider);
    final postEnabled = ref.watch(
      settingsProvider.select((s) => s.postProcessingEnabled),
    );
    final bracketSingle = ref.watch(
      settingsProvider.select((s) => s.bracketSingleMeaning),
    );
    final multiMeaningMode = ref.watch(
      settingsProvider.select((s) => s.multiMeaningDisplayMode),
    );

    final activeTabs = <_ResultTabType>[
      _ResultTabType.singleMeaning,
      _ResultTabType.multiMeaning,
      if (postEnabled) _ResultTabType.postProcessing,
      if (_gtTabOpen) _ResultTabType.googleTranslate,
    ];

    if (_tabController.length != activeTabs.length) {
      final old = _tabController;
      final newIndex = old.index.clamp(0, activeTabs.length - 1);
      _tabController = _makeController(
        length: activeTabs.length,
        initialIndex: newIndex,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }

    final activeIndex = _tabController.index.clamp(0, activeTabs.length - 1);
    final activeTab = activeTabs[activeIndex];

    final isMultiMeaning = activeTab == _ResultTabType.multiMeaning;
    final String Function(Token) textOf = isMultiMeaning
        ? (t) => t.displayAllWith(
            bracketSingle: bracketSingle,
            mode: multiMeaningMode,
          )
        : (t) => t.displayWithPartOfSpeech;

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
                tabs: [for (final tab in activeTabs) Tab(text: tab.label)],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.g_translate, size: 20),
              tooltip: 'Dịch cả đoạn bằng Google Translate (tab mới)',
              onPressed: state.hasResult ? _openGoogleTranslateTab : null,
            ),
          ],
        ),
        if (activeTab == _ResultTabType.googleTranslate)
          Expanded(child: _buildGoogleTranslateView(context))
        else if (activeTab == _ResultTabType.postProcessing)
          Expanded(child: _buildPostProcessingView(context, state))
        else if (!state.hasResult)
          const Expanded(
            child: Center(child: Text('Kết quả dịch sẽ hiện ở đây')),
          )
        else
          Expanded(
            child: TokenTextView(
              tokens: state.tokens,
              textOf: textOf,
              paneId: PaneId.vietPhrase,
            ),
          ),
      ],
    );
  }

  Widget _buildPostProcessingView(
    BuildContext context,
    TranslationState state,
  ) {
    final settings = ref.watch(settingsProvider);
    if (!settings.postProcessingEnabled) {
      return const Center(
        child: Text('Bật “Hậu xử lý bằng regex” trong Cài đặt để sử dụng.'),
      );
    }
    if (!state.hasResult) {
      return const Center(child: Text('Kết quả hậu xử lý sẽ hiện ở đây'));
    }
    final file = ref.watch(postProcessingRuleFileProvider(state.mode));
    return file.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Không đọc được rule: $error')),
      data: (ruleFile) {
        final input = TokenTextView.plainText(
          state.tokens,
          (token) => token.display,
          keepSpecialQuotes: settings.keepSpecialQuotes,
        );
        final result = TranslationRuleEngine(
          postProcessingRules: ruleFile.document.rules,
        ).applyPostProcessing(input, disabledGroups: ruleFile.disabledGroups);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  Text(
                    '${ruleFile.document.rules.length} rule · '
                    '${result.matches.length} rule khớp',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                  const FeatureHelpButton(
                    title: 'Hướng dẫn & Ví dụ Hậu xử lý',
                    summary:
                        'Quy tắc hậu xử lý tự động thay thế/chuẩn hoá văn bản bằng Regex và Luật Nhân sau khi dịch VietPhrase.',
                    accentColor: Color(0xFF6A1B9A),
                    points: [
                      'Quy tắc áp dụng tuần tự từ trên xuống dưới trên bản dịch VietPhrase.',
                      'Thay thế tĩnh: "regex => thay_thế" hoặc "regex<TAB>thay_thế".\nVí dụ: "không có cái gì => không có gì".',
                      'Regex bắt nhóm: Dùng () để bắt nhóm, thế bằng \$1, \$2... \$9.\nVí dụ: "ngươi (\\w+) à => cậu \$1 phải không" (ngươi đi à → cậu đi phải không).',
                      'Phân nhóm & Ghi chú: Dùng [Tên nhóm] để nhóm quy tắc (bật/tắt theo nhóm) và # để viết comment.',
                      'Luật Nhân (mode Trung): Dùng mẫu {0} đại diện cho tên/đại từ động từ từ điển.\nVí dụ: "{0} đại nhân => ngài {0}" (Tiêu Viêm đại nhân → ngài Tiêu Viêm).',
                      'Thử nghiệm rule: Mở Cài đặt → Chung → "Mở rule tester" để gõ thử văn bản, kiểm tra rule nào đang khớp và sửa trực tiếp.',
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy kết quả hậu xử lý',
                    onPressed: () {
                      writeAppClipboard(ref, result.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã copy kết quả hậu xử lý'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (ruleFile.document.errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${ruleFile.document.errors.length} rule lỗi đã bị bỏ qua',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  result.text,
                  style: settings.paneTextStyleFor(PaneId.vietPhrase),
                ),
              ),
            ),
          ],
        );
      },
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
                        writeAppClipboard(ref, _gtText!);
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
