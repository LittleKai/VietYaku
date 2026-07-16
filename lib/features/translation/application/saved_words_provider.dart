import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../dictionary/application/dictionaries_provider.dart';

class SavedWord {
  final String word;
  final String? reading;
  final String meaning;
  final DateTime savedAt;

  const SavedWord({
    required this.word,
    this.reading,
    required this.meaning,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'reading': reading,
        'meaning': meaning,
        'saved_at': savedAt.toIso8601String(),
      };

  factory SavedWord.fromJson(Map<String, dynamic> json) => SavedWord(
        word: json['word'] as String,
        reading: json['reading'] as String?,
        meaning: json['meaning'] as String? ?? '',
        savedAt: DateTime.tryParse(json['saved_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Danh sách từ đã lưu (appdata/saved_words.json) + export deck vocabflip.
class SavedWordsNotifier extends AsyncNotifier<List<SavedWord>> {
  File? _file;

  @override
  Future<List<SavedWord>> build() async {
    final paths = await ref.watch(appPathsProvider.future);
    _file = File(p.join(paths.support.path, 'saved_words.json'));
    if (!_file!.existsSync()) return [];
    try {
      final list = jsonDecode(await _file!.readAsString()) as List<dynamic>;
      return list
          .map((e) => SavedWord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(SavedWord word) async {
    final current = [...state.valueOrNull ?? <SavedWord>[]];
    current.removeWhere((w) => w.word == word.word);
    current.add(word);
    state = AsyncData(current);
    await _file!.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(current.map((w) => w.toJson()).toList()));
  }

  /// Deck JSON tương thích vocabflip (khảo sát Phase 0):
  /// import qua menu Import file .json của vocabflip.
  String exportVocabflipJson({String sourceLanguage = 'ja'}) {
    final words = state.valueOrNull ?? [];
    final deck = {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'decks': [
        {
          'name': 'VietYaku — Từ đã lưu',
          'description': 'Xuất từ VietYaku',
          'source_language': sourceLanguage,
          'target_language': 'vi',
          'cards': [
            for (final w in words)
              {
                'front': w.word,
                'front_phonetic': w.reading,
                'back': w.meaning,
                'notes': null,
                'tags': <String>[],
              },
          ],
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(deck);
  }
}

final savedWordsProvider =
    AsyncNotifierProvider<SavedWordsNotifier, List<SavedWord>>(
        SavedWordsNotifier.new);
