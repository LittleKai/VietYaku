import '../domain/dict_type.dart';
import '../domain/phrase_dictionary.dart';

/// Parse nội dung từ điển dạng `key=nghĩa1/nghĩa2`.
///
/// - Strip BOM (U+FEFF) ở đầu file.
/// - Chấp nhận CRLF lẫn LF.
/// - Tách tại dấu `=` ĐẦU TIÊN; dấu `=` trong value giữ nguyên.
/// - Dòng không có `=` hoặc key rỗng → bỏ qua.
/// - Key trùng → giữ dòng đầu tiên theo thứ tự file.
PhraseDictionary parseDictionary(String content, DictType type) {
  return PhraseDictionary(type, parseEntries(content));
}

/// Parse CC-CEDICT (`trad simp [pin yin] /def1/def2/`).
///
/// - Bỏ dòng comment `#` và dòng không đúng dạng.
/// - Key: cả trad lẫn simp (trùng → giữ entry đầu).
/// - Value: `[pin yin] def1; def2; `.
Map<String, String> parseCedictEntries(String content) {
  final entries = <String, String>{};
  for (final rawLine in content.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.isEmpty || line.startsWith('#')) continue;
    final firstSpace = line.indexOf(' ');
    if (firstSpace <= 0) continue;
    final secondSpace = line.indexOf(' ', firstSpace + 1);
    if (secondSpace < 0) continue;
    final bracketOpen = line.indexOf('[', secondSpace);
    final bracketClose =
        bracketOpen < 0 ? -1 : line.indexOf(']', bracketOpen);
    if (bracketClose < 0) continue;
    final slashStart = line.indexOf('/', bracketClose);
    if (slashStart < 0) continue;

    final trad = line.substring(0, firstSpace);
    final simp = line.substring(firstSpace + 1, secondSpace);
    final pinyin = line.substring(bracketOpen + 1, bracketClose);
    final defs = line
        .substring(slashStart)
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('; ');
    if (defs.isEmpty) continue;
    final value = '[$pinyin] $defs';
    entries.putIfAbsent(trad, () => value);
    if (simp != trad) entries.putIfAbsent(simp, () => value);
  }
  return entries;
}

Map<String, String> parseEntries(String content) {
  var text = content;
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }

  final entries = <String, String>{};
  var lineStart = 0;
  final n = text.length;
  while (lineStart < n) {
    var lineEnd = text.indexOf('\n', lineStart);
    var nextStart = lineEnd + 1;
    if (lineEnd < 0) {
      lineEnd = n;
      nextStart = n;
    } else if (lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 0x0D) {
      lineEnd -= 1; // CRLF
    }
    if (lineEnd > lineStart) {
      final line = text.substring(lineStart, lineEnd);
      final eq = line.indexOf('=');
      if (eq > 0) {
        final key = line.substring(0, eq);
        entries.putIfAbsent(key, () => line.substring(eq + 1));
      }
    }
    lineStart = nextStart;
  }
  return entries;
}
