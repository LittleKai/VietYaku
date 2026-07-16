/// Trích phiên âm (romaji/pinyin) từ value LacViet — không cần morphological
/// analyzer, chỉ regex trên các pattern thực tế:
/// - `(kakugo)giác ngộ; ...`            → romaji trong ngoặc tròn đầu value
/// - `✚[fānyì] \n\t1. dịch; ...`        → pinyin trong ngoặc vuông sau ✚ đầu tiên
/// - `[fānyì] ...`                       → pinyin ngoặc vuông đầu value
/// Miss → null (không đoán).
library;

enum ReadingKind { romaji, pinyin }

final _parenAtStart = RegExp(r'^\s*\(([^)]+)\)');
final _bracketAfterPlus = RegExp(r'✚\s*\[([^\]]+)\]');
final _bracketAtStart = RegExp(r'^\s*\[([^\]]+)\]');

/// Romaji thuần ASCII (kakugo, mochiaru...) — tránh nhầm chú thích tiếng Việt
/// trong ngoặc như `(cũ)`.
final _asciiRomaji = RegExp(r"^[A-Za-z][A-Za-z' \-]*$");

({String text, ReadingKind kind})? extractReading(String value) {
  final paren = _parenAtStart.firstMatch(value);
  if (paren != null) {
    final text = paren.group(1)!.trim();
    if (_asciiRomaji.hasMatch(text)) {
      return (text: text, kind: ReadingKind.romaji);
    }
  }
  final afterPlus = _bracketAfterPlus.firstMatch(value);
  if (afterPlus != null) {
    return (text: afterPlus.group(1)!.trim(), kind: ReadingKind.pinyin);
  }
  final bracket = _bracketAtStart.firstMatch(value);
  if (bracket != null) {
    return (text: bracket.group(1)!.trim(), kind: ReadingKind.pinyin);
  }
  return null;
}

/// Value LacViet chứa literal `\n`, `\t` (2 ký tự) → đổi thành xuống dòng/tab
/// thật khi hiển thị.
String unescapeLacViet(String value) =>
    value.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
