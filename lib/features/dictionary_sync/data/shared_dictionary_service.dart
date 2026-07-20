import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';
import '../../translation/domain/translation_engine.dart';
import '../domain/shared_dictionary_entry.dart';

class SharedDictionaryService {
  final AppPaths paths;

  SharedDictionaryService(this.paths);

  File fileFor(TranslationMode mode, SharedDictionaryKind kind) {
    final label = kind == SharedDictionaryKind.vietPhrase
        ? 'SharedVietPhrase'
        : 'SharedLacViet';
    return File(
      p.join(paths.dictionariesDir.path, '${label}_${mode.name}.txt'),
    );
  }

  File pendingFileFor(TranslationMode mode, SharedDictionaryKind kind) {
    final label = kind == SharedDictionaryKind.vietPhrase
        ? 'PendingVietPhrase'
        : 'PendingLacViet';
    return File(
      p.join(paths.dictionariesDir.path, '${label}_${mode.name}.txt'),
    );
  }

  /// Lưu sửa đổi của admin vào từ điển cục bộ và hàng đợi upload.
  Future<void> stageLocalEdit(
    TranslationMode mode,
    SharedDictionaryEntry entry,
  ) async {
    await _upsert(pendingFileFor(mode, entry.kind), [entry]);
    await applyDelta(mode, [entry]);
  }

  Future<List<SharedDictionaryEntry>> pendingEntries(
    TranslationMode mode,
  ) async {
    final result = <SharedDictionaryEntry>[];
    for (final kind in SharedDictionaryKind.values) {
      final values = await _read(pendingFileFor(mode, kind));
      result.addAll(
        values.entries.map(
          (entry) => SharedDictionaryEntry(
            kind: kind,
            source: entry.key,
            target: entry.value,
          ),
        ),
      );
    }
    return result;
  }

  Future<void> clearPending(TranslationMode mode) async {
    for (final kind in SharedDictionaryKind.values) {
      final file = pendingFileFor(mode, kind);
      if (file.existsSync()) await file.delete();
    }
  }

  Future<int> applyDelta(
    TranslationMode mode,
    Iterable<SharedDictionaryEntry> entries,
  ) async {
    var changed = 0;
    for (final kind in SharedDictionaryKind.values) {
      final updates = entries.where((entry) => entry.kind == kind).toList();
      if (updates.isEmpty) continue;

      changed += await _upsert(fileFor(mode, kind), updates);
    }
    return changed;
  }

  static Future<int> _upsert(
    File file,
    Iterable<SharedDictionaryEntry> entries,
  ) async {
    final values = await _read(file);
    var changed = 0;
    for (final entry in entries) {
      if (values[entry.source] == entry.target) continue;
      values[entry.source] = entry.target;
      changed++;
    }
    if (changed > 0) await _write(file, values);
    return changed;
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
    await file.writeAsString('\uFEFF${lines.join('\r\n')}\r\n');
  }
}
