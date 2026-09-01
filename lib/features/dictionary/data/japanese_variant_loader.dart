import 'dart:io';
import 'dart:isolate';

import '../domain/japanese_variant_index.dart';

Future<JapaneseVariantIndex> loadJapaneseVariantIndex(String sourcePath) =>
    Isolate.run(() => loadJapaneseVariantIndexSync(sourcePath));

/// Đọc nhóm surface Sudachi dạng TSV; dòng lỗi bị bỏ để asset thiếu/hỏng chỉ
/// làm mất alias động, không chặn nạp các từ điển chính.
JapaneseVariantIndex loadJapaneseVariantIndexSync(String sourcePath) {
  final file = File(sourcePath);
  if (!file.existsSync()) return JapaneseVariantIndex(const []);

  var text = file.readAsStringSync();
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }
  final groups = <List<String>>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.isEmpty) continue;
    final surfaces = line.split('\t');
    if (surfaces.length >= 2 &&
        surfaces.every((surface) => surface.isNotEmpty)) {
      groups.add(surfaces);
    }
  }
  return JapaneseVariantIndex(groups);
}
