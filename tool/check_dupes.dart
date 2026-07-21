// Kiểm tra duplicate key và conflict trong các file từ điển.
// Chỉ đọc, KHÔNG ghi đè gì.
//
// Chạy: dart run tool/check_dupes.dart <thư mục>
//   Ví dụ: dart run tool/check_dupes.dart data/cn
//          dart run tool/check_dupes.dart data/jp

import 'dart:io';

void main(List<String> args) {
  final dirPath = args.isNotEmpty ? args.first : 'data/cn';
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    stderr.writeln('Không tìm thấy thư mục $dirPath');
    exitCode = 1;
    return;
  }

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stdout.writeln('Không có file .txt nào trong $dirPath');
    return;
  }

  stdout.writeln('=== Check dupes/conflicts trong $dirPath ===\n');

  var grandTotalDupes = 0;
  var grandTotalConflicts = 0;

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    var content = file.readAsStringSync();
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

    final seen = <String, String>{};
    var entries = 0;
    var dupes = 0;
    var conflicts = 0;
    final conflictExamples = <String>[];

    for (var line in lines) {
      if (line.isNotEmpty && line.codeUnitAt(line.length - 1) == 0x0D) {
        line = line.substring(0, line.length - 1);
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      entries++;
      final key = line.substring(0, eq);
      final value = line.substring(eq + 1);

      final existing = seen[key];
      if (existing != null) {
        if (existing == value) {
          dupes++;
        } else {
          conflicts++;
          if (conflictExamples.length < 10) {
            // Truncate value for display
            final v1 = existing.length > 60
                ? '${existing.substring(0, 60)}...'
                : existing;
            final v2 =
                value.length > 60 ? '${value.substring(0, 60)}...' : value;
            conflictExamples.add('  $key\n    [1] $v1\n    [2] $v2');
          }
        }
      } else {
        seen[key] = value;
      }
    }

    if (dupes == 0 && conflicts == 0) {
      stdout.writeln('$name: $entries entries — sạch ✓');
      continue;
    }

    stdout.writeln('$name: $entries entries');
    if (dupes > 0) stdout.writeln('  dupes (same value): $dupes');
    if (conflicts > 0) {
      stdout.writeln('  conflicts (diff value): $conflicts');
      for (final ex in conflictExamples) {
        stdout.writeln(ex);
      }
      if (conflicts > conflictExamples.length) {
        stdout.writeln(
            '  ... và ${conflicts - conflictExamples.length} conflict nữa');
      }
    }
    stdout.writeln('');

    grandTotalDupes += dupes;
    grandTotalConflicts += conflicts;
  }

  stdout.writeln('\n=== Tổng kết ===');
  stdout.writeln('Dupes (same value): $grandTotalDupes');
  stdout.writeln('Conflicts (diff value): $grandTotalConflicts');
}
