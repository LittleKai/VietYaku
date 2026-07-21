// Chạy repair (simp→JP) cho tất cả file .txt trong data/jp/ chưa repair.
// VietPhrase.txt và LacViet.txt đã repair trước đó → bỏ qua.
//
// Policy: convert (chỉ giữ key đã chuyển sang kiểu Nhật, bỏ key giản thể).
// ThieuChuu.txt, Babylon.txt: conflict (trùng key, khác value) được GHÉP
// bằng \n\t thay vì bỏ — giữ cả hai định nghĩa.
//
// Chạy: dart run tool/repair_all_jp.dart

import 'dart:io';

import 'package:vietyaku/features/repair/domain/jp_repair_pipeline.dart';
import 'package:vietyaku/features/repair/domain/repair_report.dart';
import 'package:vietyaku/features/repair/domain/simp2jp_table.dart';

/// Các file đã repair (bỏ qua).
const _alreadyRepaired = {'VietPhrase.txt', 'LacViet.txt'};

/// Các file không phải format key=value (bỏ qua).
const _skipFiles = {'cedict_ts.u8'};

/// Các file mà conflict sẽ được GHÉP thay vì bỏ.
const _mergeConflictFiles = {'ThieuChuu.txt', 'Babylon.txt'};

/// Giống [repairFile] nhưng conflict (trùng key, khác value) được ghép
/// bằng `\n\t` thay vì bỏ dòng sau.
RepairedFile _repairFileWithMerge(
  String content,
  Simp2JpTable table,
  RepairPolicy policy,
) {
  var text = content;
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  final report = RepairReport()..totalLines = lines.length;
  final output = <String>[];
  // key → index in output list + current merged value.
  final seenIndex = <String, int>{};
  final seenValue = <String, String>{};

  void emit(String key, String value, {required bool isVariant}) {
    final existing = seenValue[key];
    if (existing != null) {
      if (existing == value) {
        report.dupesIdenticalValue++;
      } else {
        // MERGE: nối bằng \n\t (literal).
        final merged = '$existing\\n\\t$value';
        final idx = seenIndex[key]!;
        output[idx] = '$key=$merged';
        seenValue[key] = merged;
        report.conflicts.add('$key (merged)');
      }
      return;
    }
    seenIndex[key] = output.length;
    seenValue[key] = value;
    output.add('$key=$value');
    if (isVariant) report.variantsAdded++;
  }

  for (var lineNo = 0; lineNo < lines.length; lineNo++) {
    var line = lines[lineNo];
    if (line.isNotEmpty && line.codeUnitAt(line.length - 1) == 0x0D) {
      line = line.substring(0, line.length - 1);
    }

    final eq = line.indexOf('=');
    if (eq <= 0) {
      if (line.isNotEmpty || lineNo < lines.length - 1) output.add(line);
      continue;
    }
    report.entryLines++;
    final rawKey = line.substring(0, eq);
    final value = line.substring(eq + 1);

    final (spaceFixed, removed) = fixKeySpaces(rawKey);
    report.spacesRemoved += removed;

    if (containsKana(spaceFixed)) {
      final (converted, count) = convertKeyChars(spaceFixed, table, report);
      report.charsConverted += count;
      emit(converted, value, isVariant: false);
    } else {
      switch (policy) {
        case RepairPolicy.keepOnly:
          convertKeyChars(spaceFixed, table, report);
          emit(spaceFixed, value, isVariant: false);
        case RepairPolicy.convert:
          final (converted, count) = convertKeyChars(spaceFixed, table, report);
          report.charsConverted += count;
          emit(converted, value, isVariant: false);
        case RepairPolicy.addVariant:
          final (converted, count) = convertKeyChars(spaceFixed, table, report);
          emit(spaceFixed, value, isVariant: false);
          if (converted != spaceFixed) {
            report.charsConverted += count;
            emit(converted, value, isVariant: true);
          }
      }
    }
  }

  final body = output.join('\r\n');
  return RepairedFile(body.isEmpty ? body : '$body\r\n', report);
}

void main() {
  final table = Simp2JpTable.parse(
    File('assets/mappings/simp2jp.tsv').readAsStringSync(),
    overridesTsv:
        File('assets/mappings/simp2jp_overrides.tsv').readAsStringSync(),
  );

  final dir = Directory('data/jp');
  if (!dir.existsSync()) {
    stderr.writeln('Không tìm thấy thư mục data/jp/');
    exitCode = 1;
    return;
  }

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .where((f) {
        final name = f.uri.pathSegments.last;
        return !_alreadyRepaired.contains(name) && !_skipFiles.contains(name);
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stdout.writeln('Không có file nào cần xử lý.');
    return;
  }

  stdout.writeln('=== Repair simp→JP cho ${files.length} file ===\n');

  var totalConverted = 0;
  var totalSpaces = 0;
  var totalDupes = 0;
  var totalConflicts = 0;
  var totalMerged = 0;
  var totalVariants = 0;

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final content = file.readAsStringSync();
    final sw = Stopwatch()..start();
    final shouldMerge = _mergeConflictFiles.contains(name);

    final result = shouldMerge
        ? _repairFileWithMerge(content, table, RepairPolicy.convert)
        : repairFile(content, table, RepairPolicy.convert);
    final elapsed = sw.elapsedMilliseconds;
    final report = result.report;

    if (!report.hasChanges &&
        report.dupesIdenticalValue == 0 &&
        report.conflicts.isEmpty) {
      stdout.writeln('$name: không đổi (${elapsed}ms)');
      continue;
    }

    // Ghi đè file với BOM
    file.writeAsStringSync('\uFEFF${result.content}');

    stdout.writeln('$name: ${elapsed}ms');
    stdout.writeln('  entries: ${report.entryLines}');
    if (report.spacesRemoved > 0) {
      stdout.writeln('  spaces removed: ${report.spacesRemoved}');
    }
    if (report.charsConverted > 0) {
      stdout.writeln('  chars converted: ${report.charsConverted}');
    }
    if (report.dupesIdenticalValue > 0) {
      stdout.writeln('  dupes (same value): ${report.dupesIdenticalValue}');
    }
    if (report.conflicts.isNotEmpty) {
      final label = shouldMerge ? 'merged' : 'conflicts (dropped)';
      stdout.writeln('  $label: ${report.conflicts.length}');
      for (final c in report.conflicts.take(5)) {
        stdout.writeln('    · $c');
      }
      if (report.conflicts.length > 5) {
        stdout.writeln('    ... và ${report.conflicts.length - 5} nữa');
      }
    }
    if (report.variantsAdded > 0) {
      stdout.writeln('  variants added: ${report.variantsAdded}');
    }
    if (report.ambiguous.isNotEmpty) {
      stdout.writeln('  ambiguous: ${report.ambiguous.length}');
      for (final e in report.ambiguous.entries.take(5)) {
        stdout.writeln('    · ${e.key} → ${e.value}');
      }
    }
    stdout.writeln('');

    totalConverted += report.charsConverted;
    totalSpaces += report.spacesRemoved;
    totalDupes += report.dupesIdenticalValue;
    if (shouldMerge) {
      totalMerged += report.conflicts.length;
    } else {
      totalConflicts += report.conflicts.length;
    }
    totalVariants += report.variantsAdded;
  }

  stdout.writeln('=== Tổng kết ===');
  stdout.writeln('Chars converted: $totalConverted');
  stdout.writeln('Spaces removed: $totalSpaces');
  stdout.writeln('Dupes removed: $totalDupes');
  stdout.writeln('Conflicts merged: $totalMerged');
  stdout.writeln('Conflicts dropped: $totalConflicts');
  if (totalVariants > 0) stdout.writeln('Variants added: $totalVariants');
}
