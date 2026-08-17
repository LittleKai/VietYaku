import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../translation/domain/translation_engine.dart';
import '../domain/glossary_term.dart';

/// Đọc/ghi `Global Glossary.json` của AI_Translation_Bridge (thư mục `Glossary/`
/// với hai thư mục con `JP` và `CN`).
///
/// File này do tool Python quản lý: UTF-8 không BOM, `indent=2`, xuống dòng CRLF
/// (`open(..., "w")` trên Windows), không có newline cuối file. Ghi lại đúng
/// định dạng đó để lần lưu sau bên Python không đẻ ra diff toàn file.
class GlossaryService {
  static const globalGlossaryFileName = 'Global Glossary.json';

  final String rootDir;

  const GlossaryService(this.rootDir);

  static String langFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? 'JP' : 'CN';

  File fileFor(TranslationMode mode) =>
      File(p.join(rootDir, langFor(mode), globalGlossaryFileName));

  /// Thư mục đã trỏ đúng chỗ khi `Global Glossary.json` của [mode] tồn tại.
  bool hasGlossaryFor(TranslationMode mode) =>
      rootDir.trim().isNotEmpty && fileFor(mode).existsSync();

  /// Mục từ hiện có trong glossary, khớp theo `source` (bỏ hoa/thường như
  /// `GlossaryManager.merge_terms` bên Python). `null` nếu chưa có.
  Future<GlossaryTerm?> find(TranslationMode mode, String source) async {
    final key = source.trim().toLowerCase();
    if (key.isEmpty) return null;
    final payload = await _readPayload(mode);
    if (payload == null) return null;
    for (final raw in _termsOf(payload)) {
      final term = GlossaryTerm.fromJson(raw);
      if (term.source.trim().toLowerCase() == key) return term;
    }
    return null;
  }

  /// Thêm mới hoặc cập nhật `target` của [source], luôn đặt `created_by = user`.
  /// Các field khác của mục có sẵn (kind, notes, date_added) giữ nguyên.
  Future<void> upsert(
    TranslationMode mode, {
    required String source,
    required String target,
  }) => upsertAll(mode, {source: target});

  /// Như [upsert] nhưng ghi nhiều mục trong một lần đọc/ghi file — dùng cho
  /// màn đồng bộ hàng loạt (file glossary hơn 5000 mục, ghi từng cái rất chậm).
  Future<void> upsertAll(
    TranslationMode mode,
    Map<String, String> targetBySource,
  ) async {
    if (targetBySource.isEmpty) return;
    final payload = await _readPayload(mode);
    if (payload == null) {
      throw const FileSystemException('Không đọc được file Global Glossary.');
    }
    final terms = _termsOf(payload);
    final indexByKey = <String, int>{};
    for (var i = 0; i < terms.length; i++) {
      final key = (terms[i]['source'] ?? '').toString().trim().toLowerCase();
      indexByKey.putIfAbsent(key, () => i);
    }

    for (final entry in targetBySource.entries) {
      final source = entry.key.trim();
      final target = entry.value.trim();
      if (source.isEmpty || target.isEmpty) continue;
      final index = indexByKey[source.toLowerCase()];
      if (index != null) {
        terms[index] = GlossaryTerm.fromJson(terms[index])
            .copyWith(target: target, createdBy: 'user')
            .toJson();
      } else {
        indexByKey[source.toLowerCase()] = terms.length;
        terms.add(
          GlossaryTerm(
            source: source,
            target: target,
            dateAdded: todayStamp(),
          ).toJson(),
        );
      }
    }
    payload['terms'] = terms;
    final file = fileFor(mode);
    _payloadCache[file.path] = payload;

    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await file.writeAsString(
      text.replaceAll('\n', '\r\n'),
      encoding: utf8,
      flush: true,
    );
  }

  /// Toàn bộ mục từ trong glossary của [mode] (rỗng nếu chưa trỏ đúng thư mục).
  Future<List<GlossaryTerm>> readAll(TranslationMode mode) async {
    final payload = await _readPayload(mode);
    if (payload == null) return const [];
    return _termsOf(payload).map(GlossaryTerm.fromJson).toList();
  }

  /// Xóa các mục từ khỏi glossary theo [sources].
  Future<void> removeAll(
    TranslationMode mode,
    Iterable<String> sources,
  ) async {
    if (sources.isEmpty) return;
    final payload = await _readPayload(mode);
    if (payload == null) return;
    final keysToRemove = sources.map((s) => s.trim().toLowerCase()).toSet();
    final terms = _termsOf(payload);
    terms.removeWhere(
      (term) => keysToRemove.contains(
        (term['source'] ?? '').toString().trim().toLowerCase(),
      ),
    );
    payload['terms'] = terms;
    final file = fileFor(mode);
    _payloadCache[file.path] = payload;

    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await file.writeAsString(
      text.replaceAll('\n', '\r\n'),
      encoding: utf8,
      flush: true,
    );
  }

  static String todayStamp() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static final Map<String, Map<String, dynamic>> _payloadCache = {};

  /// Xóa cache trong bộ nhớ (dùng khi settings đổi đường dẫn hoặc reset).
  static void clearCache() => _payloadCache.clear();

  Future<Map<String, dynamic>?> _readPayload(TranslationMode mode) async {
    final file = fileFor(mode);
    final path = file.path;
    if (_payloadCache.containsKey(path)) {
      return _payloadCache[path];
    }
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString(encoding: utf8));
      if (decoded is Map<String, dynamic>) {
        _payloadCache[path] = decoded;
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> _termsOf(Map<String, dynamic> payload) {
    final raw = payload['terms'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}
