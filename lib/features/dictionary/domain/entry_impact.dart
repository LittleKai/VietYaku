import '../../../core/cjk.dart';
import '../../translation/domain/translation_engine.dart';

class EntryImpact {
  final String key;
  final String meaning;
  final String? baseValue;
  final String? currentLayerValue;
  final int occurrences;
  final List<String> errors;
  final List<String> warnings;

  const EntryImpact({
    required this.key,
    required this.meaning,
    required this.baseValue,
    required this.currentLayerValue,
    required this.occurrences,
    required this.errors,
    required this.warnings,
  });

  bool get canSave => key.isNotEmpty && meaning.isNotEmpty && errors.isEmpty;
}

EntryImpact previewEntryImpact({
  required String rawKey,
  required String rawMeaning,
  required String sourceText,
  required TranslationMode mode,
  String? baseValue,
  String? currentLayerValue,
}) {
  final key = rawKey.trim();
  final meaning = rawMeaning.trim();
  final errors = <String>[];
  final warnings = <String>[];
  if (rawKey.contains('=') || rawKey.contains('\n') || rawKey.contains('\r')) {
    errors.add('Key không được chứa dấu = hoặc xuống dòng.');
  }
  if (rawMeaning.contains('\n') || rawMeaning.contains('\r')) {
    errors.add('Nghĩa không được xuống dòng; dùng chuỗi \\n nếu cần.');
  }
  if (rawKey != key) {
    warnings.add('Khoảng trắng đầu/cuối key sẽ bị loại bỏ.');
  }
  if (rawMeaning != meaning) {
    warnings.add('Khoảng trắng đầu/cuối nghĩa sẽ bị loại bỏ.');
  }
  if (key.isNotEmpty) {
    final hasHan = _contains(key, isHanCodePoint);
    final hasKana = _contains(key, isKanaCodePoint);
    if (mode == TranslationMode.japanese && !hasHan && !hasKana) {
      warnings.add('Key không chứa chữ Hán/Kana dù đang ở mode Nhật.');
    }
    if (mode == TranslationMode.chinese && hasKana) {
      warnings.add('Key chứa Kana dù đang ở mode Trung.');
    } else if (mode == TranslationMode.chinese && !hasHan) {
      warnings.add('Key không chứa chữ Hán dù đang ở mode Trung.');
    }
  }

  return EntryImpact(
    key: key,
    meaning: meaning,
    baseValue: baseValue,
    currentLayerValue: currentLayerValue,
    occurrences: countOccurrences(sourceText, key),
    errors: errors,
    warnings: warnings,
  );
}

int countOccurrences(String text, String key) {
  if (key.isEmpty || text.isEmpty || key.length > text.length) return 0;
  var count = 0;
  var start = 0;
  while (start <= text.length - key.length) {
    final found = text.indexOf(key, start);
    if (found < 0) break;
    count++;
    start = found + 1;
  }
  return count;
}

bool _contains(String text, bool Function(int) predicate) {
  for (var i = 0; i < text.length; i++) {
    if (predicate(codePointAt(text, i))) return true;
    i += runeLengthAt(text, i) - 1;
  }
  return false;
}
