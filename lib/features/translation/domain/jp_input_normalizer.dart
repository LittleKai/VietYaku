import 'token.dart';

/// Chuẩn hoá input tiếng Nhật trước khi tra từ điển (mục 2.5
/// docs/NGHIEN_CUU_SUDACHI.md): halfwidth katakana U+FF66–FF9F → fullwidth,
/// ghép dakuten/handakuten liền sau (`ｶ`+`ﾞ` → `ガ`: 2 code unit gốc → 1 code
/// unit chuẩn hoá). Giữ bảng offset để token trỏ đúng về văn bản gốc (§3.1).
class NormalizedInput {
  /// Văn bản đã chuẩn hoá (đưa vào engine tra từ điển).
  final String text;

  /// `toOriginal[i]` = offset trong văn bản gốc của code unit thứ `i` trong
  /// [text]; phần tử cuối = độ dài văn bản gốc (map biên phải của token).
  final List<int> toOriginal;

  /// false = không có gì để chuẩn hoá, dùng thẳng văn bản gốc.
  final bool changed;

  const NormalizedInput(this.text, this.toOriginal, this.changed);
}

/// Fullwidth katakana tương ứng U+FF66..U+FF9D (ｦｧｨｩｪｫｬｭｮｯｰｱ..ﾝ).
const _halfToFull = <int>[
  0x30F2, 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30E3, 0x30E5, // ｦｧｨｩｪｫｬｭ
  0x30E7, 0x30C3, 0x30FC, 0x30A2, 0x30A4, 0x30A6, 0x30A8, 0x30AA, // ｮｯｰｱｲｳｴｵ
  0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3, 0x30B5, 0x30B7, 0x30B9, // ｶｷｸｹｺｻｼｽ
  0x30BB, 0x30BD, 0x30BF, 0x30C1, 0x30C4, 0x30C6, 0x30C8, 0x30CA, // ｾｿﾀﾁﾂﾃﾄﾅ
  0x30CB, 0x30CC, 0x30CD, 0x30CE, 0x30CF, 0x30D2, 0x30D5, 0x30D8, // ﾆﾇﾈﾉﾊﾋﾌﾍ
  0x30DB, 0x30DE, 0x30DF, 0x30E0, 0x30E1, 0x30E2, 0x30E4, 0x30E6, // ﾎﾏﾐﾑﾒﾓﾔﾕ
  0x30E8, 0x30E9, 0x30EA, 0x30EB, 0x30EC, 0x30ED, 0x30EF, 0x30F3, // ﾖﾗﾘﾙﾚﾛﾜﾝ
];

/// Katakana fullwidth ghép được dakuten (ﾞ): voiced = base + 1.
const _voicableByOne = <int>{
  0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3, // カキクケコ
  0x30B5, 0x30B7, 0x30B9, 0x30BB, 0x30BD, // サシスセソ
  0x30BF, 0x30C1, 0x30C4, 0x30C6, 0x30C8, // タチツテト
  0x30CF, 0x30D2, 0x30D5, 0x30D8, 0x30DB, // ハヒフヘホ
};

/// Hàng ハ行 ghép được handakuten (ﾟ): semi-voiced = base + 2.
const _semiVoicable = <int>{0x30CF, 0x30D2, 0x30D5, 0x30D8, 0x30DB};

NormalizedInput normalizeJapaneseInput(String text) {
  final n = text.length;
  final sb = StringBuffer();
  final toOriginal = <int>[];
  var changed = false;
  var i = 0;
  while (i < n) {
    final cu = text.codeUnitAt(i);
    if (cu >= 0xFF66 && cu <= 0xFF9D) {
      var full = _halfToFull[cu - 0xFF66];
      var consumed = 1;
      if (i + 1 < n) {
        final mark = text.codeUnitAt(i + 1);
        if (mark == 0xFF9E) {
          if (full == 0x30A6) {
            full = 0x30F4; // ｳﾞ → ヴ
            consumed = 2;
          } else if (_voicableByOne.contains(full)) {
            full += 1;
            consumed = 2;
          }
        } else if (mark == 0xFF9F && _semiVoicable.contains(full)) {
          full += 2;
          consumed = 2;
        }
      }
      sb.writeCharCode(full);
      toOriginal.add(i);
      i += consumed;
      changed = true;
      continue;
    }
    sb.writeCharCode(cu);
    toOriginal.add(i);
    i += 1;
  }
  toOriginal.add(n);
  return NormalizedInput(sb.toString(), toOriginal, changed);
}

/// Map token (dịch trên văn bản đã chuẩn hoá) về offset + source của văn bản
/// gốc bằng bảng [NormalizedInput.toOriginal].
List<Token> remapTokensToOriginal(
  List<Token> tokens,
  String original,
  List<int> toOriginal,
) => [
  for (final t in tokens)
    Token(
      source: original.substring(
        toOriginal[t.sourceStart],
        toOriginal[t.sourceStart + t.source.length],
      ),
      sourceStart: toOriginal[t.sourceStart],
      kind: t.kind,
      dictType: t.dictType,
      rawValue: t.rawValue,
    ),
];
