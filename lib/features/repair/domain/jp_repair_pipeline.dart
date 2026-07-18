import '../../../core/cjk.dart';
import 'repair_report.dart';
import 'simp2jp_table.dart';

/// Chính sách với key thuần Hán (không kana — không chắc chắn là tiếng Nhật).
enum RepairPolicy {
  /// Giữ dòng gốc (đã sửa space) + chèn dòng đã convert ngay sau (mặc định).
  addVariant,

  /// Chỉ giữ dòng đã convert.
  convert,

  /// Không convert key thuần Hán (chỉ sửa space).
  keepOnly,
}

class RepairedFile {
  final String content;
  final RepairReport report;

  const RepairedFile(this.content, this.report);
}

/// (A) Xóa run space (U+0020, U+3000) khi CẢ HAI ký tự liền kề đều KHÔNG
/// phải ASCII alphanumeric [A-Za-z0-9]; space chạm chữ/số Latin giữ nguyên.
/// Run ở đầu/cuối key → xóa (trim). Trả về (key mới, số space đã xóa).
(String, int) fixKeySpaces(String key) {
  final buffer = StringBuffer();
  var removed = 0;
  var i = 0;
  final n = key.length;
  while (i < n) {
    final unit = key.codeUnitAt(i);
    if (unit == 0x20 || unit == 0x3000) {
      var runEnd = i;
      while (runEnd < n) {
        final u = key.codeUnitAt(runEnd);
        if (u != 0x20 && u != 0x3000) break;
        runEnd++;
      }
      final hasPrev = buffer.isNotEmpty;
      final hasNext = runEnd < n;
      final prevAlnum = hasPrev && isAsciiAlphanumeric(key.codeUnitAt(i - 1));
      final nextAlnum = hasNext && isAsciiAlphanumeric(key.codeUnitAt(runEnd));
      final keep = hasPrev && hasNext && (prevAlnum || nextAlnum);
      if (keep) {
        buffer.write(key.substring(i, runEnd));
      } else {
        removed += runEnd - i;
      }
      i = runEnd;
    } else {
      buffer.writeCharCode(unit);
      i++;
    }
  }
  return (buffer.toString(), removed);
}

bool containsKana(String key) {
  for (var i = 0; i < key.length; i++) {
    if (isKanaCodePoint(key.codeUnitAt(i))) return true;
  }
  return false;
}

/// (B) Convert per-char theo bảng; ambiguous giữ nguyên + ghi vào [report].
(String, int) convertKeyChars(
  String key,
  Simp2JpTable table,
  RepairReport report,
) {
  final buffer = StringBuffer();
  var converted = 0;
  var i = 0;
  while (i < key.length) {
    final len = runeLengthAt(key, i);
    final char = key.substring(i, i + len);
    final jp = table.convert(char);
    if (jp != null) {
      buffer.write(jp);
      converted++;
    } else {
      if (table.isAmbiguous(char)) {
        report.ambiguous.putIfAbsent(
          char,
          () => '${table.ambiguous[char]!.join("|")} (vd: $key)',
        );
      }
      buffer.write(char);
    }
    i += len;
  }
  return (buffer.toString(), converted);
}

/// Sửa toàn file từ điển `key=value`.
///
/// - Tách tại dấu `=` ĐẦU TIÊN; dòng không có `=` → pass through nguyên vẹn.
/// - VALUE KHÔNG ĐỔI 1 BYTE.
/// - Dedupe: key trùng (kể cả trùng sau repair) → giữ dòng đầu theo thứ tự
///   file; value giống hệt → đếm dupe, khác → log conflict.
/// - Kết quả nối CRLF (caller thêm BOM khi ghi file).
RepairedFile repairFile(
  String content,
  Simp2JpTable table,
  RepairPolicy policy, {
  void Function(int processed, int total)? onProgress,
}) {
  var text = content;
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  final report = RepairReport()..totalLines = lines.length;
  final output = <String>[];
  final seen = <String, String>{};

  void emit(String key, String value, {required bool isVariant}) {
    final existing = seen[key];
    if (existing != null) {
      if (existing == value) {
        report.dupesIdenticalValue++;
      } else {
        report.conflicts.add('$key=$value');
      }
      return;
    }
    seen[key] = value;
    output.add('$key=$value');
    if (isVariant) report.variantsAdded++;
  }

  for (var lineNo = 0; lineNo < lines.length; lineNo++) {
    var line = lines[lineNo];
    if (line.isNotEmpty && line.codeUnitAt(line.length - 1) == 0x0D) {
      line = line.substring(0, line.length - 1);
    }
    if (onProgress != null && lineNo % 5000 == 0) {
      onProgress(lineNo, lines.length);
    }

    final eq = line.indexOf('=');
    if (eq <= 0) {
      // Không có `=` hoặc key rỗng → giữ nguyên vẹn (bỏ dòng trống cuối).
      if (line.isNotEmpty || lineNo < lines.length - 1) output.add(line);
      continue;
    }
    report.entryLines++;
    final rawKey = line.substring(0, eq);
    final value = line.substring(eq + 1); // không đổi 1 byte

    final (spaceFixed, removed) = fixKeySpaces(rawKey);
    report.spacesRemoved += removed;

    if (containsKana(spaceFixed)) {
      // Có kana → chắc chắn tiếng Nhật → convert luôn.
      final (converted, count) = convertKeyChars(spaceFixed, table, report);
      report.charsConverted += count;
      emit(converted, value, isVariant: false);
    } else {
      switch (policy) {
        case RepairPolicy.keepOnly:
          convertKeyChars(spaceFixed, table, report); // chỉ để ghi ambiguous
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
  onProgress?.call(lines.length, lines.length);

  final body = output.join('\r\n');
  return RepairedFile(body.isEmpty ? body : '$body\r\n', report);
}
