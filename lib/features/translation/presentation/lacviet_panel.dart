import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/tts_button.dart';
import '../application/lookup_controller.dart';
import '../application/saved_words_provider.dart';
import '../application/translation_controller.dart';
import '../domain/translation_engine.dart';

/// Panel tra LacViet: ô tra nhanh + header (từ + reading + 🔊) + nội dung.
class LacVietPanel extends ConsumerStatefulWidget {
  const LacVietPanel({super.key});

  @override
  ConsumerState<LacVietPanel> createState() => _LacVietPanelState();
}

class _LacVietPanelState extends ConsumerState<LacVietPanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveWord(
      BuildContext context, WidgetRef ref, LookupResult result) async {
    final meaning = (result.body ?? '').split('\n').first.trim();
    await ref.read(savedWordsProvider.notifier).add(SavedWord(
          word: result.matchedKey ?? result.word,
          reading: result.reading,
          meaning: meaning.isEmpty ? (result.hanViet ?? '') : meaning,
          savedAt: DateTime.now(),
        ));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Đã lưu "${result.matchedKey ?? result.word}"'),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _exportVocabflip(
      BuildContext context, WidgetRef ref, TranslationMode mode) async {
    final words = ref.read(savedWordsProvider).valueOrNull ?? [];
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa có từ nào được lưu')));
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'vietyaku_deck.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json'])
      ],
    );
    if (location == null) return;
    final json = ref.read(savedWordsProvider.notifier).exportVocabflipJson(
        sourceLanguage: mode == TranslationMode.japanese ? 'ja' : 'zh');
    await File(location.path).writeAsString(json);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã xuất ${words.length} từ → ${location.path}')));
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(lookupControllerProvider);
    final mode =
        ref.watch(translationControllerProvider.select((s) => s.mode));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Tra từ nhanh…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (word) {
              if (word.trim().isNotEmpty) {
                ref
                    .read(lookupControllerProvider.notifier)
                    .lookup(word.trim());
              }
            },
          ),
        ),
        if (result == null)
          const Expanded(
            child: Center(
              child: Text('Click token ở kết quả dịch\nhoặc tra từ nhanh',
                  textAlign: TextAlign.center),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.matchedKey ?? result.word,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (result.reading != null || result.hanViet != null)
                        Text(
                          [
                            if (result.reading != null) result.reading!,
                            if (result.hanViet != null)
                              'Hán Việt: ${result.hanViet}',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                TtsButton(
                  textProvider: () => result.matchedKey ?? result.word,
                  mode: mode,
                  tooltip: 'Đọc từ',
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Sửa nghĩa (UserDict — ưu tiên cao nhất)',
                  onPressed: () => showEntryEditDialog(context, ref,
                      word: result.word, toNames: false),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_add),
                  tooltip: 'Lưu từ (từ + reading + nghĩa)',
                  onPressed: () => _saveWord(context, ref, result),
                ),
                IconButton(
                  icon: const Icon(Icons.file_download),
                  tooltip: 'Xuất từ đã lưu ra file JSON vocabflip',
                  onPressed: () => _exportVocabflip(context, ref, mode),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                result.body ?? 'Không có trong LacViet.',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
