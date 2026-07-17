import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/fnv_hash.dart';
import '../domain/dict_type.dart';
import '../domain/phrase_dictionary.dart';
import 'binary_cache.dart';
import 'dict_parser.dart';

class LoadResult {
  final PhraseDictionary dictionary;
  final bool fromCache;
  final int elapsedMs;

  const LoadResult(this.dictionary, {required this.fromCache, required this.elapsedMs});
}

/// Load một từ điển trong isolate riêng: đọc cache .vydc nếu còn hiệu lực,
/// không thì parse file text và ghi cache mới. Kết quả trả về qua
/// Isolate.run → Isolate.exit (transfer ownership, không copy).
Future<LoadResult> loadDictionary({
  required String sourcePath,
  required String cachePath,
  required DictType type,
}) {
  return Isolate.run(() => loadDictionarySync(
        sourcePath: sourcePath,
        cachePath: cachePath,
        type: type,
      ));
}

/// Bản đồng bộ (chạy được trong isolate lẫn test).
LoadResult loadDictionarySync({
  required String sourcePath,
  required String cachePath,
  required DictType type,
}) {
  final sw = Stopwatch()..start();
  final srcFile = File(sourcePath);
  if (!srcFile.existsSync()) {
    return LoadResult(PhraseDictionary(type, {}),
        fromCache: false, elapsedMs: 0);
  }

  final stat = srcFile.statSync();
  final srcSize = stat.size;
  final srcMtimeMs = stat.modified.millisecondsSinceEpoch;

  Uint8List? srcBytes;
  Uint8List readSrcBytes() => srcBytes ??= srcFile.readAsBytesSync();

  final cacheFile = File(cachePath);
  if (cacheFile.existsSync()) {
    final cacheBytes = cacheFile.readAsBytesSync();
    if (BinaryCache.isValid(cacheBytes,
        srcSize: srcSize, srcMtimeMs: srcMtimeMs, readSrcBytes: readSrcBytes)) {
      final entries = BinaryCache.decode(cacheBytes);
      if (entries != null) {
        return LoadResult(PhraseDictionary(type, entries),
            fromCache: true, elapsedMs: sw.elapsedMilliseconds);
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
  try {
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsBytesSync(BinaryCache.encode(
      entries,
      srcHash: fnv1a64(bytes),
      srcSize: srcSize,
      srcMtimeMs: srcMtimeMs,
    ));
  } on FileSystemException {
    // Ghi cache thất bại không chặn việc dùng dict.
  }
  return LoadResult(PhraseDictionary(type, entries),
      fromCache: false, elapsedMs: sw.elapsedMilliseconds);
}
