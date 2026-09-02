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
  ///
  /// [inDir] là thư mục đích: bỏ trống → `userdata/dictionaries` (dữ liệu cá
  /// nhân); admin truyền `data/<lang>/generated` để mục tra được đóng gói theo
  /// bản phát hành (xem `generatedDictDir` trong settings_provider).
  File onlineDictFile(TranslationMode mode, {String? inDir}) => File(
    p.join(inDir ?? paths.dictionariesDir.path, 'OnlineDict_${mode.name}.txt'),
  );

  Future<void> upsertOnlineDict(
    TranslationMode mode,
    String key,
    String value, {
    String? inDir,
  }) => _upsert(onlineDictFile(mode, inDir: inDir), key, value);

  /// Đoạn phân tích đầy đủ của các lần tra AI (JSON), chỉ dùng cho ô Nghĩa.
  File aiDictFile(TranslationMode mode, {String? inDir}) => File(
    p.join(inDir ?? paths.dictionariesDir.path, 'AiDict_${mode.name}.txt'),
  );

  Future<void> upsertAiDict(
    TranslationMode mode,
    String key,
    String value, {
    String? inDir,
  }) => _upsert(aiDictFile(mode, inDir: inDir), key, value);

  /// Các từ/cụm con AI tách ra, format `key=nghĩa ngắn` — file NÀY mới là thứ
  /// engine dịch nạp vào.
  File aiEntriesFile(TranslationMode mode, {String? inDir}) => File(
    p.join(inDir ?? paths.dictionariesDir.path, 'AiEntries_${mode.name}.txt'),
  );

  Future<void> upsertAiEntries(
    TranslationMode mode,
    Map<String, String> entries, {
    String? inDir,
  }) => _upsertAll(aiEntriesFile(mode, inDir: inDir), entries);

  /// Overlay VietPhrase cho các từ tra được mà bộ VietPhrase gốc chưa có.
  ///
  /// Nạp chồng lên VietPhrase nên từ mới được dịch như một mục VietPhrase bình
  /// thường. KHÔNG đụng `VietPhrase.txt` nguồn và không vào hàng đợi publish —
  /// admin bấm Update mới đẩy dữ liệu lên server.
  File vietPhraseOverlayFile(TranslationMode mode, {String? inDir}) => File(
    p.join(inDir ?? paths.dictionariesDir.path, 'VietPhrase_${mode.name}.txt'),
  );

  Future<void> upsertVietPhraseOverlay(
    TranslationMode mode,
    Map<String, String> entries, {
    String? inDir,
  }) => _upsertAll(vietPhraseOverlayFile(mode, inDir: inDir), entries);

  /// Xóa [key] khỏi các file do tra AI/online sinh ra mà engine dịch có nạp.
  ///
  /// `stageLocalDelete` chỉ gỡ mục khỏi SharedVietPhrase; từ do AI tạo lại nằm
  /// ở overlay riêng nên nếu không xóa ở đây thì bấm "Xóa từ" xong nó vẫn được
  /// dịch như cũ. KHÔNG đụng `AiDict`/`OnlineDict`: đó là bản ghi nghĩa đã tra,
  /// xóa mục dịch không có nghĩa là vứt luôn kết quả tra cứu.
  ///
  /// Trả về true nếu có file nào thực sự đổi.
  Future<bool> removeGeneratedEntry(
    TranslationMode mode,
    String key, {
    String? inDir,
  }) async {
    var changed = false;
    for (final file in [
      vietPhraseOverlayFile(mode, inDir: inDir),
      aiEntriesFile(mode, inDir: inDir),
    ]) {
      if (await _removeKey(file, key)) changed = true;
    }
    return changed;
  }

  static Future<bool> _removeKey(File file, String key) async {
    if (!file.existsSync()) return false;
    var text = await file.readAsString();
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }

    final kept = <String>[];
    var removed = false;
    for (final raw in text.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) continue;
      if (line.startsWith('$key=')) {
        removed = true;
        continue;
      }
      kept.add(line);
    }
    if (!removed) return false;

    await file.writeAsString(
      kept.isEmpty ? '﻿' : '﻿${kept.join('\r\n')}\r\n',
    );
    return true;
  }

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
