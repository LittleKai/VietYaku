/// CJK character classification theo UTF-16 / code point.
///
/// Phạm vi theo thiết kế đã chốt:
/// - Han: U+3400–4DBF, U+4E00–9FFF, U+F900–FAFF
/// - Hiragana: U+3040–309F
/// - Katakana: U+30A0–30FF, U+31F0–31FF
/// - Ký hiệu lặp 々 U+3005, 〇 U+3007, trường âm ー U+30FC
library;

bool isHanCodePoint(int cp) =>
    (cp >= 0x3400 && cp <= 0x4DBF) ||
    (cp >= 0x4E00 && cp <= 0x9FFF) ||
    (cp >= 0xF900 && cp <= 0xFAFF) ||
    cp == 0x3005 ||
    cp == 0x3007;

bool isKanaCodePoint(int cp) =>
    (cp >= 0x3040 && cp <= 0x309F) ||
    (cp >= 0x30A0 && cp <= 0x30FF) ||
    (cp >= 0x31F0 && cp <= 0x31FF) ||
    cp == 0x30FC;

bool isCjkCodePoint(int cp) => isHanCodePoint(cp) || isKanaCodePoint(cp);

bool isAsciiAlphanumeric(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
    (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
    (codeUnit >= 0x61 && codeUnit <= 0x7A); // a-z

/// Code point tại vị trí code-unit [index]; ghép surrogate pair nếu có.
int codePointAt(String text, int index) {
  final lead = text.codeUnitAt(index);
  if (lead >= 0xD800 && lead <= 0xDBFF && index + 1 < text.length) {
    final trail = text.codeUnitAt(index + 1);
    if (trail >= 0xDC00 && trail <= 0xDFFF) {
      return 0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00);
    }
  }
  return lead;
}

/// Số code unit của rune bắt đầu tại [index] (1 hoặc 2).
int runeLengthAt(String text, int index) {
  final lead = text.codeUnitAt(index);
  if (lead >= 0xD800 && lead <= 0xDBFF && index + 1 < text.length) {
    final trail = text.codeUnitAt(index + 1);
    if (trail >= 0xDC00 && trail <= 0xDFFF) return 2;
  }
  return 1;
}
