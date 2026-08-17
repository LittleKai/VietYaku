import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/dictionary_repository.dart';
import '../../settings/settings_provider.dart';
import '../application/translation_controller.dart';
import '../application/translation_rules_provider.dart';
import '../data/translation_rule_repository.dart';
import '../domain/translation_engine.dart';
import '../domain/translation_rule.dart';
import 'token_text_view.dart';

enum _TesterKind { regex, person }

Future<void> showTranslationRuleTesterDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final mode = ref.read(currentModeProvider);
  final paths = await ref.read(appPathsProvider.future);
  final dictionaries = await ref.read(dictionariesProvider.future);
  final repository = TranslationRuleRepository(paths);
  final file = await repository.loadPostProcessing(mode);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TranslationRuleTesterDialog(
      mode: mode,
      dictionaries: dictionaries,
      repository: repository,
      initialSource: file.document.source,
      initialDisabledGroups: file.disabledGroups,
      onSaved: () => ref.invalidate(postProcessingRuleFileProvider(mode)),
    ),
  );
}

class TranslationRuleTesterDialog extends ConsumerStatefulWidget {
  final TranslationMode mode;
  final LoadedDictionaries dictionaries;
  final TranslationRuleRepository repository;
  final String initialSource;
  final Set<String> initialDisabledGroups;
  final VoidCallback onSaved;

  const TranslationRuleTesterDialog({
    super.key,
    required this.mode,
    required this.dictionaries,
    required this.repository,
    required this.initialSource,
    required this.initialDisabledGroups,
    required this.onSaved,
  });

  @override
  ConsumerState<TranslationRuleTesterDialog> createState() =>
      _TranslationRuleTesterDialogState();
}

class _TranslationRuleTesterDialogState
    extends ConsumerState<TranslationRuleTesterDialog> {
  late final TextEditingController _rulesController;
  final _inputController = TextEditingController();
  _TesterKind _kind = _TesterKind.regex;
  String _output = '';
  String _trace = '';
  bool _saving = false;
  late final Set<String> _disabledGroups;

  @override
  void initState() {
    super.initState();
    _rulesController = TextEditingController(text: widget.initialSource);
    _disabledGroups = {...widget.initialDisabledGroups};
  }

  @override
  void dispose() {
    _rulesController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _test() {
    if (_kind == _TesterKind.regex) {
      final document = parsePostProcessingRules(_rulesController.text);
      final result = TranslationRuleEngine(postProcessingRules: document.rules)
          .applyPostProcessing(
            _inputController.text,
            disabledGroups: _disabledGroups,
          );
      setState(() {
        _output = result.text;
        _trace = document.errors.isNotEmpty
            ? document.errors
                  .map((e) => 'Dòng ${e.line}: ${e.message}')
                  .join('\n')
            : result.matches.isEmpty
            ? 'Không có rule khớp.'
            : result.matches
                  .map(
                    (m) => 'Dòng ${m.rule.line} [${m.rule.group}] ×${m.count}',
                  )
                  .join('\n');
      });
      return;
    }
    final scope = ref.read(settingsProvider).personRuleScope;
    final engine = widget.dictionaries.engineWith(personRuleScope: scope);
    final tokens = engine.translate(_inputController.text, mode: widget.mode);
    final dictionaries = widget.dictionaries.personRuleDictsFor(scope);
    final matched = <String>[];
    for (var i = 0; i < _inputController.text.length; i++) {
      final match = widget.dictionaries.ruleEngine.matchPersonRuleAt(
        _inputController.text,
        i,
        dictionaries,
      );
      if (match != null) {
        matched.add('Dòng ${match.rule.line}: ${match.rule.pattern}');
      }
    }
    setState(() {
      _output = TokenTextView.plainText(tokens, (token) => token.display);
      _trace = scope == PersonRuleScope.off
          ? 'Luật Nhân đang tắt trong Cài đặt.'
          : matched.isEmpty
          ? 'Không có Luật Nhân khớp.'
          : matched.toSet().join('\n');
    });
  }

  Future<void> _save() async {
    final document = parsePostProcessingRules(_rulesController.text);
    if (document.errors.isNotEmpty) {
      setState(() {
        _trace = document.errors
            .map((e) => 'Dòng ${e.line}: ${e.message}')
            .join('\n');
      });
      return;
    }
    final isUnchanged = _rulesController.text.trim() == widget.initialSource.trim() &&
        _disabledGroups.length == widget.initialDisabledGroups.length &&
        _disabledGroups.containsAll(widget.initialDisabledGroups);
    if (isUnchanged) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    await widget.repository.savePostProcessing(
      widget.mode,
      _rulesController.text,
      disabledGroups: _disabledGroups,
    );
    widget.onSaved();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã lưu quy tắc hậu xử lý')));
  }

  @override
  Widget build(BuildContext context) {
    final modeLabel = widget.mode == TranslationMode.japanese
        ? 'Tiếng Nhật'
        : 'Tiếng Trung';
    final regexDocument = parsePostProcessingRules(_rulesController.text);
    final groups = regexDocument.rules.map((rule) => rule.group).toSet();
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      title: Text('Quy tắc dịch · $modeLabel'),
      content: SizedBox(
        width: math.min(820, MediaQuery.sizeOf(context).width * 0.82),
        height: math.min(620, MediaQuery.sizeOf(context).height * 0.72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_TesterKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _TesterKind.regex, label: Text('Regex')),
                ButtonSegment(
                  value: _TesterKind.person,
                  label: Text('Luật Nhân'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) => setState(() {
                _kind = value.first;
                _output = '';
                _trace = '';
              }),
            ),
            const SizedBox(height: 12),
            if (_kind == _TesterKind.regex) ...[
              const Text(
                'Mỗi dòng: regex<TAB>thay thế (hoặc regex => thay thế). '
                'Dùng [Tên nhóm], # để ghi chú, và \$1…\$9 cho capture.',
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final group in groups)
                      FilterChip(
                        label: Text(group),
                        selected: !_disabledGroups.contains(group),
                        onSelected: (enabled) => setState(() {
                          if (enabled) {
                            _disabledGroups.remove(group);
                          } else {
                            _disabledGroups.add(group);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Expanded(
                child: TextField(
                  controller: _rulesController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: 'Consolas'),
                  decoration: const InputDecoration(
                    hintText: '[Dấu câu]\n\\s+([,.!?])\\s* => \$1',
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${widget.dictionaries.ruleEngine.personRules.length} rule '
                  'đã nạp. Placeholder {0} chỉ bắt mục thuộc phạm vi đã chọn.',
                ),
              ),
            TextField(
              controller: _inputController,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _kind == _TesterKind.regex
                    ? 'Văn bản kết quả cần hậu xử lý'
                    : 'Câu nguồn cần dịch thử',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _test,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Chạy thử'),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _output.isEmpty ? 'Kết quả sẽ hiện ở đây.' : _output,
            ),
            if (_trace.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_trace, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Đang lưu…' : 'Lưu regex'),
        ),
      ],
    );
  }
}
