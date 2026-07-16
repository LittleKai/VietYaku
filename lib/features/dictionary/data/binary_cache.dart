import 'dart:convert';
import 'dart:typed_data';

import '../../../core/fnv_hash.dart';

/// Binary snapshot `.vydc` cho từ điển đã parse.
///
/// Header (little-endian):
///   magic 'VYDC' u32 | version u16 | srcHash u64 (FNV-1a) | srcSize u64 |
///   srcMtime i64 (ms since epoch) | count u32
/// Body: (keyLen u16 | keyBytes UTF-8 | valLen u32 | valBytes UTF-8) × count
class BinaryCache {
  /// 'V','Y','D','C' đọc như u32 little-endian.
  static const int magic = 0x43445956;
  static const int version = 1;
  static const int headerLength = 4 + 2 + 8 + 8 + 8 + 4;

  static Uint8List encode(
    Map<String, String> entries, {
    required int srcHash,
    required int srcSize,
    required int srcMtimeMs,
  }) {
    final builder = BytesBuilder(copy: false);
    final header = ByteData(headerLength);
    header.setUint32(0, magic, Endian.little);
    header.setUint16(4, version, Endian.little);
    header.setUint64(6, srcHash, Endian.little);
    header.setUint64(14, srcSize, Endian.little);
    header.setInt64(22, srcMtimeMs, Endian.little);
    header.setUint32(30, entries.length, Endian.little);
    builder.add(header.buffer.asUint8List());

    for (final entry in entries.entries) {
      final keyBytes = utf8.encode(entry.key);
      final valBytes = utf8.encode(entry.value);
      final lens = ByteData(6);
      lens.setUint16(0, keyBytes.length, Endian.little);
      lens.setUint32(2, valBytes.length, Endian.little);
      builder.add(lens.buffer.asUint8List());
      builder.add(keyBytes);
      builder.add(valBytes);
    }
    return builder.takeBytes();
  }

  /// Metadata nguồn lưu trong cache; null nếu bytes không phải .vydc hợp lệ.
  static ({int srcHash, int srcSize, int srcMtimeMs, int count})? readHeader(
      Uint8List bytes) {
    if (bytes.length < headerLength) return null;
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != magic) return null;
    if (data.getUint16(4, Endian.little) != version) return null;
    return (
      srcHash: data.getUint64(6, Endian.little),
      srcSize: data.getUint64(14, Endian.little),
      srcMtimeMs: data.getInt64(22, Endian.little),
      count: data.getUint32(30, Endian.little),
    );
  }

  /// Decode body. Trả null nếu dữ liệu cụt/hỏng.
  static Map<String, String>? decode(Uint8List bytes) {
    final header = readHeader(bytes);
    if (header == null) return null;
    final entries = <String, String>{};
    var offset = headerLength;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < header.count; i++) {
      if (offset + 6 > bytes.length) return null;
      final keyLen = data.getUint16(offset, Endian.little);
      final valLen = data.getUint32(offset + 2, Endian.little);
      offset += 6;
      if (offset + keyLen + valLen > bytes.length) return null;
      final key = utf8.decode(bytes.sublist(offset, offset + keyLen));
      offset += keyLen;
      final value = utf8.decode(bytes.sublist(offset, offset + valLen));
      offset += valLen;
      entries[key] = value;
    }
    return entries;
  }

  /// Cache còn hiệu lực với file nguồn hiện tại không.
  ///
  /// So size trước; size khớp mà mtime lệch mới tính FNV-1a của nguồn
  /// (Google Drive sync hay đổi mtime dù nội dung y nguyên).
  static bool isValid(
    Uint8List cacheBytes, {
    required int srcSize,
    required int srcMtimeMs,
    required Uint8List Function() readSrcBytes,
  }) {
    final header = readHeader(cacheBytes);
    if (header == null) return false;
    if (header.srcSize != srcSize) return false;
    if (header.srcMtimeMs == srcMtimeMs) return true;
    return fnv1a64(readSrcBytes()) == header.srcHash;
  }
}
