import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';
import '../../translation/domain/translation_engine.dart';
import '../domain/glossary_term_change.dart';

/// Hàng đợi sửa đổi Global Glossary chờ đẩy lên server, mỗi mode một file
/// `PendingGlossary_<mode>.txt` cạnh các file `Pending*` của từ điển chung.
///
/// Cùng định dạng `key=value` UTF-8 BOM CRLF như `SharedDictionaryService` để
/// mở file ra vẫn đọc được bằng mắt; mục xóa lưu bằng sentinel.
class GlossaryTermQueue {
  static const _deleteSentinel = '\x7F__DELETE__';

  final AppPaths paths;

  const GlossaryTermQueue(this.paths);

  File fileFor(TranslationMode mode) => File(
    p.join(paths.dictionariesDir.path, 'PendingGlossary_${mode.name}.txt'),
  );

  /// Xếp hàng các mục vừa ghi vào `Global Glossary.json`. Mục sai định dạng bị
  /// bỏ qua — xem [GlossaryTermChange.isValid].
  Future<void> enqueue(
    TranslationMode mode, {
    Map<String, String> upserts = const {},
    Iterable<String> deletes = const [],
  }) async {
    final values = await _read(fileFor(mode));
    var changed = false;
    for (final entry in upserts.entries) {
      final change = GlossaryTermChange(
        source: entry.key.trim(),
        target: entry.value.trim(),
      );
      if (!change.isValid) continue;
      values[change.source] = change.target;
      changed = true;
    }
    for (final raw in deletes) {
      final change = GlossaryTermChange(source: raw.trim(), isDelete: true);
      if (!change.isValid) continue;
      values[change.source] = _deleteSentinel;
      changed = true;
    }
    if (changed) await _write(fileFor(mode), values);
  }

  Future<List<GlossaryTermChange>> pending(TranslationMode mode) async {
    final values = await _read(fileFor(mode));
    return [
      for (final entry in values.entries)
        entry.value == _deleteSentinel
            ? GlossaryTermChange(source: entry.key, isDelete: true)
            : GlossaryTermChange(source: entry.key, target: entry.value),
    ];
  }

  Future<void> clear(TranslationMode mode) async {
    final file = fileFor(mode);
    if (file.existsSync()) await file.delete();
  }

  static Future<Map<String, String>> _read(File file) async {
    final result = <String, String>{};
    if (!file.existsSync()) return result;
    var text = await file.readAsString();
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    for (final raw in text.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      result[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return result;
  }

  static Future<void> _write(File file, Map<String, String> values) async {
    await file.parent.create(recursive: true);
    final lines = values.entries.map((entry) => '${entry.key}=${entry.value}');
    final content = '\uFEFF${lines.join('\r\n')}\r\n';
    final tmpFile = File('${file.path}.tmp');
    await tmpFile.writeAsString(content, flush: true);
    await tmpFile.rename(file.path);
  }
}
