import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/project_segment.dart';

class TranslationMemoryFormatException implements Exception {
  const TranslationMemoryFormatException(this.message);

  final String message;

  @override
  String toString() => 'TranslationMemoryFormatException: $message';
}

class TranslationMemoryStore {
  const TranslationMemoryStore(this.root);

  final Directory root;

  File get _file => File(p.join(root.path, 'tm.jsonl'));

  Future<void> upsertReviewedAll(Iterable<ProjectSegment> segments) async {
    final valid = [
      for (final segment in segments)
        if (segment.status == ProjectSegmentStatus.reviewed &&
            segment.editedTarget.trim().isNotEmpty)
          segment,
    ];
    if (valid.isEmpty) return;
    final entries = await _read();
    for (final segment in valid) {
      entries[segment.source] = segment;
    }
    await root.create(recursive: true);
    final lines = entries.values.map((value) => jsonEncode(value.toJson()));
    await _writeAtomic('${lines.join('\n')}\n');
  }

  Future<String?> lookupExact(String source) async {
    final segment = (await _read())[source];
    return segment?.editedTarget;
  }

  Future<Map<String, ProjectSegment>> _read() async {
    if (!await _file.exists()) return {};
    final entries = <String, ProjectSegment>{};
    try {
      for (final line in await _file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        final value = jsonDecode(line);
        if (value is! Map) {
          throw const FormatException('TM record không phải object');
        }
        final segment = ProjectSegment.fromJson(
          Map<String, Object?>.from(value),
        );
        if (segment.status == ProjectSegmentStatus.reviewed) {
          entries[segment.source] = segment;
        }
      }
      return entries;
    } catch (error) {
      throw TranslationMemoryFormatException('$error');
    }
  }

  Future<void> _writeAtomic(String content) async {
    final temporary = File('${_file.path}.tmp');
    final backup = File('${_file.path}.bak');
    await temporary.writeAsString(content, flush: true);
    if (await backup.exists()) await backup.delete();
    if (await _file.exists()) await _file.rename(backup.path);
    try {
      await temporary.rename(_file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await _file.exists()) {
        await backup.rename(_file.path);
      }
      rethrow;
    }
  }
}
