import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/feature_help_button.dart';
import '../../clipboard/application/clipboard_reader_controller.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/domain/dict_type.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/translation_engine.dart';
import '../application/dictionary_search_provider.dart';
import '../domain/dictionary_search.dart';

class DictionarySearchScreen extends ConsumerStatefulWidget {
  const DictionarySearchScreen({super.key});

  @override
  ConsumerState<DictionarySearchScreen> createState() =>
      _DictionarySearchScreenState();
}

class _DictionarySearchScreenState
    extends ConsumerState<DictionarySearchScreen> {
  final _queryController = TextEditingController();
  DictionarySearchMode _searchMode = DictionarySearchMode.exactKey;
  Set<DictType> _selectedTypes = {};
  DictionarySearchQuery? _submittedQuery;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _search() {
    final text = _queryController.text.trim();
    if (text.isEmpty) return;
    final mode = ref.read(currentModeProvider);
    final activeTypes = _selectedTypes
        .where((type) => type.isAvailableFor(mode))
        .toSet();
    setState(() {
      _submittedQuery = DictionarySearchQuery(
        text: text,
        mode: _searchMode,
        dictionaryTypes: Set.unmodifiable(activeTypes),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(currentModeProvider);
    final dictionaries = ref.watch(dictionariesProvider);
    final availableTypes =
        dictionaries.valueOrNull?.searchLayers
            .where((layer) => layer.entries.isNotEmpty)
            .map((layer) => layer.type)
            .where((type) => type.isAvailableFor(mode))
            .toSet()
            .toList()
          ?..sort((a, b) => a.index.compareTo(b.index));
    final response = _submittedQuery == null
        ? null
        : ref.watch(dictionarySearchProvider(_submittedQuery!));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Search Center'),
            SizedBox(width: 4),
            FeatureHelpButton(
              title: 'Search Center / tra ngược từ điển',
              summary:
                  'Tìm trong toàn bộ lớp từ điển mà không thay đổi engine dịch.',
              accentColor: Color(0xFF5E35B1),
              points: [
                'Key chính xác tìm đúng một key; “bắt đầu bằng” tìm theo tiền tố.',
                'Wildcard: * đại diện cho chuỗi bất kỳ, ? đại diện cho một ký tự. Ví dụ *龍* hoặc 少?.',
                'Toàn văn trong nghĩa là tra ngược từ tiếng Việt và không phân biệt chữ hoa/thường.',
                'Có thể lọc theo mode Nhật/Trung và từng loại từ điển khả dụng cho ngôn ngữ đó.',
                'Nhãn “Lớp đang thắng” cho biết base/shared/user overlay nào thực sự được áp dụng.',
                'Việc quét chạy trong worker isolate riêng; engine HashMap và đường dịch nóng không bị thay đổi.',
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SegmentedButton<TranslationMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: TranslationMode.japanese,
                  label: Text('Tiếng Nhật'),
                ),
                ButtonSegment(
                  value: TranslationMode.chinese,
                  label: Text('Tiếng Trung'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) async {
                final nextMode = selection.first;
                setState(() {
                  _submittedQuery = null;
                  _selectedTypes = _selectedTypes
                      .where((type) => type.isAvailableFor(nextMode))
                      .toSet();
                });
                await ref
                    .read(translationControllerProvider.notifier)
                    .setMode(nextMode);
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _search(),
                            decoration: InputDecoration(
                              labelText:
                                  _searchMode ==
                                      DictionarySearchMode.fullTextValue
                                  ? 'Nội dung nghĩa cần tìm'
                                  : 'Key từ điển cần tìm',
                              hintText:
                                  _searchMode ==
                                      DictionarySearchMode.wildcardKey
                                  ? 'Ví dụ: *龍* hoặc 少?'
                                  : null,
                              prefixIcon: const Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<DictionarySearchMode>(
                            initialValue: _searchMode,
                            decoration: const InputDecoration(
                              labelText: 'Kiểu tìm',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: DictionarySearchMode.exactKey,
                                child: Text('Key chính xác'),
                              ),
                              DropdownMenuItem(
                                value: DictionarySearchMode.prefixKey,
                                child: Text('Key bắt đầu bằng'),
                              ),
                              DropdownMenuItem(
                                value: DictionarySearchMode.wildcardKey,
                                child: Text('Wildcard (* và ?)'),
                              ),
                              DropdownMenuItem(
                                value: DictionarySearchMode.fullTextValue,
                                child: Text('Toàn văn trong nghĩa'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _searchMode = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: dictionaries.isLoading ? null : _search,
                          icon: const Icon(Icons.manage_search),
                          label: const Text('Tìm'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Từ điển:',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        FilterChip(
                          label: const Text('Tất cả'),
                          selected: _selectedTypes.isEmpty,
                          onSelected: (_) =>
                              setState(() => _selectedTypes = {}),
                        ),
                        for (final type in availableTypes ?? const <DictType>[])
                          FilterChip(
                            label: Text(_dictTypeLabel(type)),
                            selected: _selectedTypes.contains(type),
                            onSelected: (selected) {
                              setState(() {
                                final next = {..._selectedTypes};
                                selected ? next.add(type) : next.remove(type);
                                _selectedTypes = next;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (response) {
                null => const _SearchHint(),
                AsyncLoading() => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Đang quét từ điển trong tiến trình nền…'),
                    ],
                  ),
                ),
                AsyncError(:final error) => Center(
                  child: Text('Không thể tìm kiếm: $error'),
                ),
                AsyncData(:final value) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        value.isTruncated
                            ? '${value.totalMatches} kết quả — đang hiện ${value.results.length}'
                            : '${value.totalMatches} kết quả',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: value.results.isEmpty
                          ? const Center(
                              child: Text('Không tìm thấy mục phù hợp.'),
                            )
                          : ListView.separated(
                              itemCount: value.results.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final result = value.results[index];
                                return Card(
                                  child: ListTile(
                                    title: SelectableText(result.key),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        result.value.replaceAll(r'\n', '\n'),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    leading: CircleAvatar(
                                      child: Text('${index + 1}'),
                                    ),
                                    trailing: SizedBox(
                                      width: 190,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            result.layerLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (result.isWinningLayer)
                                            Text(
                                              'Lớp đang thắng',
                                              style: TextStyle(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    onTap: () {
                                      writeAppClipboard(ref, result.key);
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          const SnackBar(
                                            content: Text('Đã chép key'),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Tra key theo chính xác, tiền tố hoặc wildcard;\n'
      'chọn “Toàn văn trong nghĩa” để tra ngược từ tiếng Việt.',
      textAlign: TextAlign.center,
    ),
  );
}

String _dictTypeLabel(DictType type) => switch (type) {
  DictType.userDict => 'UserDict',
  DictType.names => 'Names',
  DictType.vietPhrase => 'VietPhrase',
  DictType.lacViet => 'Lạc Việt',
  DictType.mazii => 'Mazii',
  DictType.chinesePhienAm => 'Hán Việt',
  DictType.pronouns => 'Đại từ',
  DictType.babylon => 'Babylon',
  DictType.thieuChuu => 'Thiều Chửu',
  DictType.cedict => 'CEDICT',
  DictType.chinesePhienAmEnglish => 'Phiên âm Anh',
  DictType.jaVi => 'Nhật Việt',
  DictType.zhVi => 'Trung Việt',
  DictType.onlineDict => 'Online đã lưu',
};
