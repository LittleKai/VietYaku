/// Gộp run số kanji không match từ điển thành 1 token số Ả Rập (mục 2.4
/// docs/NGHIEN_CUU_SUDACHI.md, theo JoinNumericPlugin của Sudachi):
/// `三百二十五` → "325", `一万二千` → "12000", `一九八四` → "1984".
/// Chỉ áp cho run ≥ 2 token kind hanViet/unmatched liền kề — cụm đã match
/// VietPhrase (vd `一人`) giữ nguyên.
library;

import '../../../core/cjk.dart';
import 'token.dart';

const _digitValues = <int, int>{
  0x3007: 0, // 〇
  0x4E00: 1, // 一
  0x4E8C: 2, // 二
  0x4E09: 3, // 三
  0x56DB: 4, // 四
  0x4E94: 5, // 五
  0x516D: 6, // 六
  0x4E03: 7, // 七
  0x516B: 8, // 八
  0x4E5D: 9, // 九
};

const _smallMultipliers = <int, int>{
  0x5341: 10, // 十
  0x767E: 100, // 百
  0x5343: 1000, // 千
};

const _bigMultipliers = <int, int>{
  0x4E07: 10000, // 万
  0x5104: 100000000, // 億
  0x5146: 1000000000000, // 兆
};

/// Membership theo category KANJINUMERIC (cjk.dart); các map giá trị ở trên
/// phủ đúng tập [kanjiNumericCodeUnits].
bool isKanjiNumeralCodeUnit(int cu) =>
    charCategoryOf(cu) == CjkCharCategory.kanjiNumeric;

/// Đổi chuỗi số kanji thành chuỗi số Ả Rập. Trả null khi không hợp lệ
/// (vd `十百`, chuỗi trộn kiểu liệt kê với kiểu vị trí) — giữ nguyên token.
String? parseKanjiNumber(String s) {
  if (s.isEmpty) return null;
  var hasMultiplier = false;
  for (var i = 0; i < s.length; i++) {
    final cu = s.codeUnitAt(i);
    if (!isKanjiNumeralCodeUnit(cu)) return null;
    if (_smallMultipliers.containsKey(cu) || _bigMultipliers.containsKey(cu)) {
      hasMultiplier = true;
    }
  }

  // Kiểu liệt kê chữ số (一九八四 → 1984, giữ số 0 đầu: 〇三 → 03).
  if (!hasMultiplier) {
    final sb = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      sb.write(_digitValues[s.codeUnitAt(i)]);
    }
    return sb.toString();
  }

  // Kiểu vị trí (三百二十五 → 325, 千九百八十四 → 1984, 一万二千 → 12000).
  const none = 1 << 62;
  var result = 0;
  var section = 0;
  var current = 0;
  var digitsInCurrent = 0;
  var lastSmall = none;
  var lastBig = none;
  for (var i = 0; i < s.length; i++) {
    final cu = s.codeUnitAt(i);
    final digit = _digitValues[cu];
    if (digit != null) {
      // Tối đa 1 chữ số trước mỗi bậc — 一二百 là trộn kiểu, không hợp lệ.
      if (digitsInCurrent >= 1) return null;
      current = digit;
      digitsInCurrent = 1;
      continue;
    }
    final small = _smallMultipliers[cu];
    if (small != null) {
      if (small >= lastSmall) return null; // 十百 không hợp lệ
      section += (current == 0 ? 1 : current) * small;
      current = 0;
      digitsInCurrent = 0;
      lastSmall = small;
      continue;
    }
    final big = _bigMultipliers[cu];
    if (big == null) return null;
    if (big >= lastBig) return null; // 万億 không hợp lệ
    final value = section + current;
    result += (value == 0 ? 1 : value) * big;
    section = 0;
    current = 0;
    digitsInCurrent = 0;
    lastSmall = none;
    lastBig = big;
  }
  return (result + section + current).toString();
}

bool _isNumeralToken(Token t) =>
    (t.kind == TokenKind.hanViet || t.kind == TokenKind.unmatched) &&
    t.source.length == 1 &&
    isKanjiNumeralCodeUnit(t.source.codeUnitAt(0));

/// Run tối đa 20 ký tự — dài hơn coi như không phải số thật.
const _maxRunLength = 20;

/// Gộp các run token số kanji liền kề (không match dict) thành 1 token với
/// [Token.rawValue] là số Ả Rập. Run parse thất bại giữ nguyên token gốc.
List<Token> joinKanjiNumerals(List<Token> tokens) {
  final out = <Token>[];
  var i = 0;
  while (i < tokens.length) {
    if (!_isNumeralToken(tokens[i])) {
      out.add(tokens[i]);
      i++;
      continue;
    }
    var end = i + 1;
    while (end < tokens.length &&
        _isNumeralToken(tokens[end]) &&
        tokens[end].sourceStart ==
            tokens[end - 1].sourceStart + tokens[end - 1].source.length) {
      end++;
    }
    if (end - i >= 2 && end - i <= _maxRunLength) {
      final source = tokens.sublist(i, end).map((t) => t.source).join();
      final parsed = parseKanjiNumber(source);
      if (parsed != null) {
        out.add(
          Token(
            source: source,
            sourceStart: tokens[i].sourceStart,
            kind: TokenKind.matched,
            rawValue: parsed,
          ),
        );
        i = end;
        continue;
      }
    }
    out.addAll(tokens.sublist(i, end));
    i = end;
  }
  return out;
}
