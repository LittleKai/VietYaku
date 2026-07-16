import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';

/// Ghi overlay UserDict.txt / UserNames.txt trong appdata
/// (không bao giờ đụng file từ điển gốc). Format `key=value` UTF-8 BOM CRLF.
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

  static Future<void> _upsert(File file, String key, String value) async {
    final lines = <String>[];
    if (file.existsSync()) {
      var text = await file.readAsString();
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
      for (final raw in text.split('\n')) {
        final line =
            raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
        if (line.isNotEmpty) lines.add(line);
      }
    }
    final prefix = '$key=';
    final index = lines.indexWhere((l) => l.startsWith(prefix));
    final entry = '$key=$value';
    if (index >= 0) {
      lines[index] = entry;
    } else {
      lines.add(entry);
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('﻿${lines.join('\r\n')}\r\n');
  }
}
