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

  Future<int> applyDelta(
    TranslationMode mode,
    Iterable<SharedDictionaryEntry> entries,
  ) async {
    var changed = 0;
    for (final kind in SharedDictionaryKind.values) {
      final updates = entries.where((entry) => entry.kind == kind).toList();
      if (updates.isEmpty) continue;

      final file = fileFor(mode, kind);
      final values = await _read(file);
      var fileChanged = false;
      for (final entry in updates) {
        if (values[entry.source] != entry.target) {
          values[entry.source] = entry.target;
          changed++;
          fileChanged = true;
        }
      }
      if (fileChanged) await _write(file, values);
    }
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
