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

/// Dấu câu CJK → dấu tiếng Việt (những ký tự KHÔNG nằm trong dải toàn-hình
/// FF01–FF5E; các ký tự toàn-hình được hạ về nửa-hình bằng phép trừ 0xFEE0).
const _cjkPunctuation = <int, String>{
  0x3002: '.', // 。
  0x3001: ',', // 、
  0x300C: '"', // 「
  0x300D: '"', // 」
  0xFE41: '"', // ﹁ (dạng dọc của 「)
  0xFE42: '"', // ﹂
  0xFF62: '"', // ｢ (halfwidth, ngoài dải FF01–FF5E)
  0xFF63: '"', // ｣
  0x3000: ' ', // khoảng trắng toàn-hình
  0x30FB: '·', // ・
};

/// Ngoặc kép CJK "đặc biệt" — mặc định GIỮ NGUYÊN khi hiển thị
/// (setting `keepSpecialQuotes`); tắt setting → chuyển thành `"`.
const _specialQuotes = <int, String>{
  0x300E: '"', // 『
  0x300F: '"', // 』
  0x3008: '"', // 〈
  0x3009: '"', // 〉
  0x300A: '"', // 《
  0x300B: '"', // 》
  0x301D: '"', // 〝
  0x301E: '"', // 〞
  0x301F: '"', // 〟
  0xFE43: '"', // ﹃ (dạng dọc của 『)
  0xFE44: '"', // ﹄
};

/// Chuẩn hoá đoạn văn bản passthrough để hiển thị: hạ ký tự toàn-hình
/// (ＡＡＨ, ，！？…) về nửa-hình và đổi dấu câu CJK (。、「」) sang dấu tiếng Việt.
/// [keepSpecialQuotes] giữ nguyên 『』《》〈〉〝〞〟﹃﹄ (false → đổi thành `"`).
String normalizeDisplayText(String text, {bool keepSpecialQuotes = true}) {
  final sb = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final cu = text.codeUnitAt(i);
    final punct =
        _cjkPunctuation[cu] ?? (keepSpecialQuotes ? null : _specialQuotes[cu]);
    if (punct != null) {
      sb.write(punct);
    } else if (cu >= 0xFF01 && cu <= 0xFF5E) {
      sb.writeCharCode(cu - 0xFEE0); // toàn-hình → nửa-hình ASCII
    } else {
      sb.writeCharCode(cu);
    }
  }
  return sb.toString();
}

/// Category ký tự theo mô hình `char.def` của Sudachi
/// (docs/NGHIEN_CUU_SUDACHI.md §2.7) — phân loại run ký tự cùng loại
/// (nhóm OOV katakana, gộp số kanji...). Mỗi code point thuộc đúng 1
/// category; [kanjiNumeric] ưu tiên hơn [kanji] (一/〇/万... vẫn là Hán
/// theo [isHanCodePoint]).
enum CjkCharCategory {
  space,
  numeric,
  alpha,
  hiragana,
  katakana,
  kanjiNumeric,
  kanji,
  other,
}

/// Số kanji + đơn vị (〇一二三四五六七八九十百千万億兆) — nguồn membership
/// cho `kanji_numeral.dart` (KANJINUMERIC trong char.def).
const kanjiNumericCodeUnits = <int>{
  0x3007, 0x4E00, 0x4E8C, 0x4E09, 0x56DB, 0x4E94, 0x516D, 0x4E03, // 〇一二三四五六七
  0x516B, 0x4E5D, 0x5341, 0x767E, 0x5343, 0x4E07, 0x5104, 0x5146, // 八九十百千万億兆
};

CjkCharCategory charCategoryOf(int cp) {
  if (cp == 0x20 ||
      (cp >= 0x09 && cp <= 0x0D) || // tab LF VT FF CR
      cp == 0x3000) {
    return CjkCharCategory.space;
  }
  if ((cp >= 0x30 && cp <= 0x39) || (cp >= 0xFF10 && cp <= 0xFF19)) {
    return CjkCharCategory.numeric;
  }
  if (kanjiNumericCodeUnits.contains(cp)) return CjkCharCategory.kanjiNumeric;
  if (cp >= 0x3041 && cp <= 0x309F) return CjkCharCategory.hiragana;
  // Katakana theo char.def (30A1–30FA, ー 30FC–30FF, nhỏ ㇰ-ㇿ 31F0–31FF)
  // + halfwidth ｦ-ﾟ FF66–FF9F (app xử lý trực tiếp, Sudachi normalize trước).
  if ((cp >= 0x30A1 && cp <= 0x30FA) ||
      (cp >= 0x30FC && cp <= 0x30FF) ||
      (cp >= 0x31F0 && cp <= 0x31FF) ||
      (cp >= 0xFF66 && cp <= 0xFF9F)) {
    return CjkCharCategory.katakana;
  }
  if (isHanCodePoint(cp)) return CjkCharCategory.kanji;
  // ALPHA theo char.def: ASCII + fullwidth + Latin-1 + Latin Extended
  // (1E00–1EF9 gồm chữ Việt có dấu).
  if ((cp >= 0x41 && cp <= 0x5A) ||
      (cp >= 0x61 && cp <= 0x7A) ||
      (cp >= 0xFF21 && cp <= 0xFF3A) ||
      (cp >= 0xFF41 && cp <= 0xFF5A) ||
      (cp >= 0xC0 && cp <= 0xD6) ||
      (cp >= 0xD8 && cp <= 0xF6) ||
      (cp >= 0xF8 && cp <= 0x236) ||
      (cp >= 0x1E00 && cp <= 0x1EF9)) {
    return CjkCharCategory.alpha;
  }
  return CjkCharCategory.other;
}

/// Một run ký tự liên tiếp cùng category: `[start, end)` theo UTF-16 code unit.
typedef CharCategoryRun = ({int start, int end, CjkCharCategory category});

/// Tách [text] thành các run cùng category, advance theo rune
/// (surrogate pair không bị cắt đôi).
List<CharCategoryRun> categoryRunsOf(String text) {
  final runs = <CharCategoryRun>[];
  var i = 0;
  while (i < text.length) {
    final start = i;
    final category = charCategoryOf(codePointAt(text, i));
    i += runeLengthAt(text, i);
    while (i < text.length && charCategoryOf(codePointAt(text, i)) == category) {
      i += runeLengthAt(text, i);
    }
    runs.add((start: start, end: i, category: category));
  }
  return runs;
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
