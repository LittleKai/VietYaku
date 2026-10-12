import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/project_document.dart';
import '../domain/project_segment.dart';

class ProjectFormatException implements Exception {
  const ProjectFormatException(this.message);

  final String message;

  @override
  String toString() => 'ProjectFormatException: $message';
}

class ProjectStore {
  const ProjectStore(this.root);

  final Directory root;

  File get _metadata => File(p.join(root.path, 'project.json'));
  File get _segments => File(p.join(root.path, 'segments.jsonl'));

  Future<ProjectDocument> open() async {
    try {
      final metadata = jsonDecode(await _metadata.readAsString());
      if (metadata is! Map) {
        throw const FormatException('project.json không phải object');
      }
      final segments = <ProjectSegment>[];
      if (await _segments.exists()) {
        for (final line in await _segments.readAsLines()) {
          if (line.trim().isEmpty) continue;
          final value = jsonDecode(line);
          if (value is! Map) {
            throw const FormatException('segment không phải object');
          }
          segments.add(
            ProjectSegment.fromJson(Map<String, Object?>.from(value)),
          );
        }
      }
      final document = ProjectDocument.fromJson(
        Map<String, Object?>.from(metadata),
      );
      return document.copyWith(segments: segments);
    } on ProjectFormatException {
      rethrow;
    } catch (error) {
      throw ProjectFormatException('$error');
    }
  }

  Future<void> save(ProjectDocument document) async {
    await root.create(recursive: true);
    await _writeAtomic(_metadata, '${jsonEncode(document.toJson())}\n');
    final lines = document.segments.map(
      (segment) => jsonEncode(segment.toJson()),
    );
    await _writeAtomic(_segments, '${lines.join('\n')}\n');
  }

  Future<void> _writeAtomic(File target, String content) async {
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await temporary.writeAsString(content, flush: true);
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }
}
