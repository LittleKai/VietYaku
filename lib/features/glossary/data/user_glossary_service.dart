import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../translation/domain/translation_engine.dart';
import '../domain/glossary_term.dart';
import 'glossary_service.dart';

class _UserGlossaryCacheEntry {
  final DateTime mtime;
  final int length;
  final Map<String, dynamic> payload;

  const _UserGlossaryCacheEntry({
    required this.mtime,
    required this.length,
    required this.payload,
  });
}

/// Đọc/ghi `User Glossary.json` của AI_Translation_Bridge (`Glossary/<lang>/User Glossary.json`).
///
/// ATB ưu tiên thuật ngữ trong `User Glossary.json` trước `Global Glossary.json`.
class UserGlossaryService {
  static const userGlossaryFileName = 'User Glossary.json';

  static final Map<String, _UserGlossaryCacheEntry> _payloadCache = {};

  static void clearCache() => _payloadCache.clear();

  final String rootDir;

  const UserGlossaryService(this.rootDir);

  File fileFor(TranslationMode mode) {
    final lang = GlossaryService.langFor(mode);
    return File(p.join(rootDir, lang, userGlossaryFileName));
  }

  bool hasGlossaryFor(TranslationMode mode) =>
      rootDir.trim().isNotEmpty && fileFor(mode).existsSync();

  Future<GlossaryTerm?> find(
    TranslationMode mode,
    String source, {
    bool forceReload = false,
  }) async {
    final key = source.trim().toLowerCase();
    if (key.isEmpty) return null;
    try {
      final terms = await readAll(mode, forceReload: forceReload);
      for (final term in terms) {
        if (term.source.trim().toLowerCase() == key) return term;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<List<GlossaryTerm>> readAll(
    TranslationMode mode, {
    bool forceReload = false,
  }) async {
    final payload = await _readPayload(mode, forceReload: forceReload);
    if (payload == null) return const [];
    final raw = payload['terms'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(GlossaryTerm.fromJson)
          .where((t) => !t.isAddressForm)
          .toList();
    }
    return const [];
  }

  Future<void> upsert(
    TranslationMode mode, {
    required String source,
    required String target,
  }) async {
    if (rootDir.trim().isEmpty) return;
    final src = source.trim();
    final tgt = target.trim();
    if (src.isEmpty || tgt.isEmpty) return;

    final lang = GlossaryService.langFor(mode);
    final payload = await _readPayload(mode) ??
        <String, dynamic>{
          'name': 'User Glossary',
          'lang': lang,
          'is_shared': false,
          'terms': <dynamic>[],
        };

    final rawTerms = payload['terms'];
    final terms = rawTerms is List
        ? rawTerms.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final key = src.toLowerCase();
    var found = false;
    for (var i = 0; i < terms.length; i++) {
      final existingSource =
          (terms[i]['source'] ?? '').toString().trim().toLowerCase();
      if (existingSource == key) {
        found = true;
        terms[i] = GlossaryTerm.fromJson(terms[i])
            .copyWith(target: tgt, createdBy: 'user')
            .toJson();
        break;
      }
    }
    if (!found) {
      terms.add(
        GlossaryTerm(
          source: src,
          target: tgt,
          dateAdded: GlossaryService.todayStamp(),
        ).toJson(),
      );
    }

    payload['terms'] = terms;
    await _writePayload(mode, payload);
  }

  Future<void> remove(TranslationMode mode, String source) =>
      removeAll(mode, [source]);

  Future<void> removeAll(TranslationMode mode, Iterable<String> sources) async {
    if (rootDir.trim().isEmpty) return;
    final keys = sources
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (keys.isEmpty) return;
    final payload = await _readPayload(mode);
    if (payload == null) return;
    final rawTerms = payload['terms'];
    if (rawTerms is! List) return;
    final beforeCount = rawTerms.length;
    rawTerms.removeWhere((item) {
      if (item is Map) {
        final src = (item['source'] ?? '').toString().trim().toLowerCase();
        return keys.contains(src);
      }
      return false;
    });
    if (rawTerms.length != beforeCount) {
      await _writePayload(mode, payload);
    }
  }

  Future<Map<String, dynamic>?> _readPayload(
    TranslationMode mode, {
    bool forceReload = false,
  }) async {
    if (rootDir.trim().isEmpty) return null;
    final file = fileFor(mode);
    final normPath = p.normalize(file.path);
    if (!file.existsSync()) {
      _payloadCache.remove(normPath);
      return null;
    }

    final mtime = file.lastModifiedSync();
    final length = file.lengthSync();
    final cached = _payloadCache[normPath];
    if (!forceReload &&
        cached != null &&
        cached.mtime == mtime &&
        cached.length == length) {
      return cached.payload;
    }

    try {
      var text = await file.readAsString(encoding: utf8);
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw FileSystemException(
          'Không đọc được định dạng User Glossary: ${file.path}',
        );
      }
      _payloadCache[normPath] = _UserGlossaryCacheEntry(
        mtime: mtime,
        length: length,
        payload: decoded,
      );
      return decoded;
    } catch (_) {
      throw FileSystemException(
        'Không đọc được định dạng User Glossary: ${file.path}',
      );
    }
  }

  Future<void> _writePayload(
    TranslationMode mode,
    Map<String, dynamic> payload,
  ) async {
    final file = fileFor(mode);
    await file.parent.create(recursive: true);
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(payload).replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    final tmpFile = File('${file.path}.tmp');
    await tmpFile.writeAsString(text, encoding: utf8, flush: true);
    await tmpFile.rename(file.path);

    final normPath = p.normalize(file.path);
    final mtime = file.existsSync() ? file.lastModifiedSync() : DateTime.now();
    final length = file.existsSync() ? file.lengthSync() : 0;
    _payloadCache[normPath] = _UserGlossaryCacheEntry(
      mtime: mtime,
      length: length,
      payload: payload,
    );
  }
}
