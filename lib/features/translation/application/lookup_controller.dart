import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../domain/reading_extractor.dart';

class LookupResult {
  /// Từ được yêu cầu tra (source của token / ô tra nhanh).
  final String word;

  /// Key thực sự match trong LacViet (có thể là prefix của [word]).
  final String? matchedKey;
  final String? reading;
  final ReadingKind? readingKind;

  /// Âm Hán Việt (chỉ khi [word] là 1 chữ Hán đơn).
  final String? hanViet;

  /// Nội dung LacViet đã unescape \n\t. Null nếu không tìm thấy.
  final String? body;

  const LookupResult({
    required this.word,
    this.matchedKey,
    this.reading,
    this.readingKind,
    this.hanViet,
    this.body,
  });

  bool get found => body != null;
}

class LookupController extends Notifier<LookupResult?> {
  @override
  LookupResult? build() => null;

  /// Tra LacViet: exact trước, miss thì thử prefix ngắn dần (theo rune).
  void lookup(String word) {
    final dicts = ref.read(dictionariesProvider).valueOrNull;
    if (dicts == null || word.isEmpty) return;

    String? matchedKey;
    String? value;
    var end = word.length;
    while (end > 0) {
      final candidate = word.substring(0, end);
      final v = dicts.lacViet.entries[candidate];
      if (v != null) {
        matchedKey = candidate;
        value = v;
        break;
      }
      // Lùi 1 rune (không cắt giữa surrogate pair).
      end -= 1;
      if (end > 0) {
        final unit = word.codeUnitAt(end);
        if (unit >= 0xDC00 && unit <= 0xDFFF) end -= 1;
      }
    }

    String? hanViet;
    if (word.length == runeLengthAt(word, 0) &&
        isHanCodePoint(codePointAt(word, 0))) {
      final v = dicts.chinesePhienAm.entries[word];
      if (v != null) hanViet = v.split('/').first.trim();
    }

    final reading = value == null ? null : extractReading(value);
    state = LookupResult(
      word: word,
      matchedKey: matchedKey,
      reading: reading?.text,
      readingKind: reading?.kind,
      hanViet: hanViet,
      body: value == null ? null : unescapeLacViet(value),
    );
  }

  void clearResult() => state = null;
}

final lookupControllerProvider =
    NotifierProvider<LookupController, LookupResult?>(LookupController.new);
