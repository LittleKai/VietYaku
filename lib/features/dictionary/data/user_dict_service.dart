import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';
import '../../translation/domain/translation_engine.dart';

/// Ghi overlay UserDict.txt / UserNames.txt / `OnlineDict_<mode>.txt` trong
/// appdata (không bao giờ đụng file từ điển gốc).
/// Format `key=value` UTF-8 BOM CRLF.
class UserDictService {
  final AppPaths paths;

  UserDictService(this.paths);

  File get userDictFile =>
      File(p.join(paths.dictionariesDir.path, 'UserDict.txt'));

  File get userNamesFile =>
      File(p.join(paths.dictionariesDir.path, 'UserNames.txt'));

  Future<void> upsertUserDict(String key, String value) =>
      _upsert(userDictFile, key, value);

  Future<void> upsertUserName(String key, String value) =>
      _upsert(userNamesFile, key, value);

  /// Ghi nhiều tên riêng một lượt (bảng ứng viên tên riêng) — một lần đọc/ghi
  /// file thay vì mỗi mục một lần.
  Future<void> upsertUserNames(Map<String, String> entries) =>
      _upsertAll(userNamesFile, entries);

  /// Từ điển tích lũy từ các lần tra online, mỗi ngôn ngữ một file.
  File onlineDictFile(TranslationMode mode) =>
      File(p.join(paths.dictionariesDir.path, 'OnlineDict_${mode.name}.txt'));

  Future<void> upsertOnlineDict(
    TranslationMode mode,
    String key,
    String value,
  ) => _upsert(onlineDictFile(mode), key, value);

  static Future<void> _upsert(File file, String key, String value) =>
      _upsertAll(file, {key: value});

  static Future<void> _upsertAll(File file, Map<String, String> entries) async {
    if (entries.isEmpty) return;
    final lines = <String>[];
    if (file.existsSync()) {
      var text = await file.readAsString();
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
      for (final raw in text.split('\n')) {
        final line = raw.endsWith('\r')
            ? raw.substring(0, raw.length - 1)
            : raw;
        if (line.isNotEmpty) lines.add(line);
      }
    }
    for (final e in entries.entries) {
      final index = lines.indexWhere((l) => l.startsWith('${e.key}='));
      final entry = '${e.key}=${e.value}';
      if (index >= 0) {
        lines[index] = entry;
      } else {
        lines.add(entry);
      }
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('﻿${lines.join('\r\n')}\r\n');
  }
}
