import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/fnv_hash.dart';
import '../../translation/domain/trad2simp_table.dart';
import '../domain/dict_type.dart';
import '../domain/phrase_dictionary.dart';
import 'binary_cache.dart';
import 'dict_parser.dart';

class LoadResult {
  final PhraseDictionary dictionary;
  final bool fromCache;
  final int elapsedMs;

  const LoadResult(
    this.dictionary, {
    required this.fromCache,
    required this.elapsedMs,
  });
}

/// Load một từ điển trong isolate riêng: đọc cache .vydc nếu còn hiệu lực,
/// không thì parse file text và ghi cache mới. Kết quả trả về qua
/// Isolate.run → Isolate.exit (transfer ownership, không copy).
Future<LoadResult> loadDictionary({
  required String sourcePath,
  required String cachePath,
  required DictType type,
  Trad2SimpTable? trad2simp,
}) {
  return Isolate.run(
    () => loadDictionarySync(
      sourcePath: sourcePath,
      cachePath: cachePath,
      type: type,
      trad2simp: trad2simp,
    ),
  );
}

/// Quy key phồn thể về giản thể, tại chỗ. Key giản thể có sẵn LUÔN thắng: mọi
/// đường tra đều quy văn bản về giản thể trước, nên key phồn thể trong dict
/// vốn không bao giờ khớp được — bỏ chúng đi không mất gì, còn thêm được dạng
/// giản thể cho những mục trước giờ nằm chết.
void normalizeKeysToSimplified(
  Map<String, String> entries,
  Trad2SimpTable trad2simp,
) {
  if (trad2simp.isEmpty) return;
  final converted = <String, String>{};
  final traditionalKeys = <String>[];
  for (final entry in entries.entries) {
    final simplified = trad2simp.convert(entry.key);
    if (identical(simplified, entry.key)) continue;
    traditionalKeys.add(entry.key);
    // Hai key phồn thể có thể quy về cùng một key giản thể — giữ mục đầu tiên
    // theo thứ tự file, đúng như cách dict_parser xử lý key trùng.
    converted.putIfAbsent(simplified, () => entry.value);
  }
  for (final key in traditionalKeys) {
    entries.remove(key);
  }
  for (final entry in converted.entries) {
    entries.putIfAbsent(entry.key, () => entry.value);
  }
}

/// Bản đồng bộ (chạy được trong isolate lẫn test).
LoadResult loadDictionarySync({
  required String sourcePath,
  required String cachePath,
  required DictType type,
  Trad2SimpTable? trad2simp,
}) {
  final sw = Stopwatch()..start();
  final srcFile = File(sourcePath);
  if (!srcFile.existsSync()) {
    return LoadResult(
      PhraseDictionary(type, {}),
      fromCache: false,
      elapsedMs: 0,
    );
  }

  final stat = srcFile.statSync();
  final srcSize = stat.size;
  final srcMtimeMs = stat.modified.millisecondsSinceEpoch;

  Uint8List? srcBytes;
  Uint8List readSrcBytes() => srcBytes ??= srcFile.readAsBytesSync();

  final cacheFile = File(cachePath);
  if (cacheFile.existsSync()) {
    final cacheBytes = cacheFile.readAsBytesSync();
    if (BinaryCache.isValid(
      cacheBytes,
      srcSize: srcSize,
      srcMtimeMs: srcMtimeMs,
      readSrcBytes: readSrcBytes,
    )) {
      final entries = BinaryCache.decode(cacheBytes);
      if (entries != null) {
        return LoadResult(
          PhraseDictionary(type, entries),
          fromCache: true,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }
    }
  }

  // Cache miss: parse text nguồn rồi ghi cache mới.
  // BOM strip xử lý trong parseEntries (ký tự U+FEFF đầu chuỗi).
  final bytes = readSrcBytes();
  final content = const Utf8Codec(allowMalformed: true).decode(bytes);
  final entries = type == DictType.cedict
      ? parseCedictEntries(content)
      : parseEntries(content);
  if (trad2simp != null) normalizeKeysToSimplified(entries, trad2simp);
  try {
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsBytesSync(
      BinaryCache.encode(
        entries,
        srcHash: fnv1a64(bytes),
        srcSize: srcSize,
        srcMtimeMs: srcMtimeMs,
      ),
    );
  } on FileSystemException {
    // Ghi cache thất bại không chặn việc dùng dict.
  }
  return LoadResult(
    PhraseDictionary(type, entries),
    fromCache: false,
    elapsedMs: sw.elapsedMilliseconds,
  );
}
