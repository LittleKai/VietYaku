import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../dictionary/application/dictionaries_provider.dart';
import '../domain/jp_repair_pipeline.dart';
import '../domain/repair_report.dart';
import '../domain/simp2jp_table.dart';

final simp2jpTableProvider = FutureProvider<Simp2JpTable>((ref) async {
  final tsv = await rootBundle.loadString('assets/mappings/simp2jp.tsv');
  final overrides =
      await rootBundle.loadString('assets/mappings/simp2jp_overrides.tsv');
  return Simp2JpTable.parse(tsv, overridesTsv: overrides);
});

class RepairState {
  final String? filePath;
  final String? fileContent;
  final RepairPolicy policy;

  /// Các cặp (dòng gốc, dòng sau repair) khác nhau — tối đa 50 để preview.
  final List<(String, String)> preview;
  final bool running;
  final double progress;
  final RepairReport? report;
  final String? repairedContent;

  /// Đường dẫn *_JP.txt đã xuất (cạnh file gốc).
  final String? exportedPath;
  final String? error;

  const RepairState({
    this.filePath,
    this.fileContent,
    this.policy = RepairPolicy.addVariant,
    this.preview = const [],
    this.running = false,
    this.progress = 0,
    this.report,
    this.repairedContent,
    this.exportedPath,
    this.error,
  });

  RepairState copyWith({
    String? filePath,
    String? fileContent,
    RepairPolicy? policy,
    List<(String, String)>? preview,
    bool? running,
    double? progress,
    RepairReport? report,
    String? repairedContent,
    String? exportedPath,
    String? error,
    bool clearResults = false,
  }) =>
      RepairState(
        filePath: filePath ?? this.filePath,
        fileContent: fileContent ?? this.fileContent,
        policy: policy ?? this.policy,
        preview: preview ?? this.preview,
        running: running ?? this.running,
        progress: progress ?? this.progress,
        report: clearResults ? null : report ?? this.report,
        repairedContent:
            clearResults ? null : repairedContent ?? this.repairedContent,
        exportedPath: clearResults ? null : exportedPath ?? this.exportedPath,
        error: clearResults ? null : error ?? this.error,
      );
}

class RepairController extends Notifier<RepairState> {
  @override
  RepairState build() => const RepairState();

  Future<void> pickFile(String path) async {
    try {
      final content = await File(path).readAsString();
      state = RepairState(filePath: path, fileContent: content,
          policy: state.policy);
      await _rebuildPreview();
    } catch (e) {
      state = state.copyWith(error: 'Không đọc được file: $e');
    }
  }

  Future<void> setPolicy(RepairPolicy policy) async {
    state = state.copyWith(policy: policy, clearResults: true);
    await _rebuildPreview();
  }

  Future<void> _rebuildPreview() async {
    final content = state.fileContent;
    if (content == null) return;
    final table = await ref.read(simp2jpTableProvider.future);
    final policy = state.policy;
    final preview = await Isolate.run(() {
      // Repair từng dòng riêng lẻ → cặp (gốc, sau repair) cho 50 dòng
      // thay đổi đầu tiên. Variant chèn thêm hiển thị nối bằng ` ⧸ `.
      final diffs = <(String, String)>[];
      for (final line in _entryLines(content)) {
        if (diffs.length >= 50) break;
        if (line.indexOf('=') <= 0) continue;
        final repaired = repairFile(line, table, policy)
            .content
            .trimRight()
            .replaceAll('\r\n', ' ⧸ ');
        if (repaired != line) diffs.add((line, repaired));
      }
      return diffs;
    });
    state = state.copyWith(preview: preview);
  }

  static List<String> _entryLines(String content) {
    var text = content;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    return text
        .split('\n')
        .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
        .toList();
  }

  Future<void> run() async {
    final content = state.fileContent;
    if (content == null || state.running) return;
    final table = await ref.read(simp2jpTableProvider.future);
    state = state.copyWith(running: true, progress: 0, clearResults: true);

    try {
      final result = await _repairInIsolate(content, table, state.policy,
          (progress) => state = state.copyWith(progress: progress));
      state = state.copyWith(
        running: false,
        progress: 1,
        report: result.report,
        repairedContent: result.content,
      );
    } catch (e) {
      state = state.copyWith(running: false, error: 'Repair lỗi: $e');
    }
  }

  Future<RepairedFile> _repairInIsolate(
    String content,
    Simp2JpTable table,
    RepairPolicy policy,
    void Function(double) onProgress,
  ) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_repairEntry,
        (receivePort.sendPort, content, table, policy));
    final result = await receivePort.firstWhere((message) {
      if (message is double) {
        onProgress(message);
        return false;
      }
      return true;
    });
    receivePort.close();
    if (result is RepairedFile) return result;
    throw StateError('$result');
  }

  static void _repairEntry(
      (SendPort, String, Simp2JpTable, RepairPolicy) args) {
    final (port, content, table, policy) = args;
    try {
      final result = repairFile(content, table, policy,
          onProgress: (processed, total) =>
              port.send(total == 0 ? 1.0 : processed / total));
      Isolate.exit(port, result);
    } catch (e) {
      Isolate.exit(port, 'Repair thất bại: $e');
    }
  }

  /// Xuất `<tên>_JP.txt` UTF-8 BOM CRLF cạnh file gốc + copy vào appdata
  /// + xóa cache .vydc cũ của bản đã sửa.
  Future<void> export() async {
    final content = state.repairedContent;
    final source = state.filePath;
    if (content == null || source == null) return;
    try {
      final base = p.basenameWithoutExtension(source);
      final exportPath = p.join(p.dirname(source), '${base}_JP.txt');
      const bom = '﻿';
      await File(exportPath).writeAsString('$bom$content');

      final paths = await ref.read(appPathsProvider.future);
      final appdataPath =
          p.join(paths.dictionariesDir.path, '${base}_JP.txt');
      await File(appdataPath).writeAsString('$bom$content');

      final cacheFile = File(paths.cacheFileFor(appdataPath));
      if (cacheFile.existsSync()) await cacheFile.delete();

      state = state.copyWith(exportedPath: exportPath);
    } catch (e) {
      state = state.copyWith(error: 'Xuất file lỗi: $e');
    }
  }

  /// Nạp dict đã sửa vào app (reload toàn bộ providers).
  Future<void> loadIntoApp() async {
    if (state.exportedPath == null) await export();
    await ref.read(dictionariesProvider.notifier).reload();
  }
}

final repairControllerProvider =
    NotifierProvider<RepairController, RepairState>(RepairController.new);
