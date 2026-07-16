import '../../../core/cjk.dart';
import '../../dictionary/domain/phrase_dictionary.dart';
import 'token.dart';

enum TranslationMode { japanese, chinese }

/// Engine dịch greedy longest-match theo UTF-16 code unit.
///
/// [dicts] theo thứ tự ưu tiên (UserDict > Names > VietPhrase): cùng độ dài
/// match thì dict đứng trước thắng. [hanVietFallback] là ChinesePhienAmWords
/// cho chữ Hán đơn không match. Chữ ký translate() giữ ổn định để v2 cắm
/// AiTranslationEngine cùng interface.
class TranslationEngine {
  final List<PhraseDictionary> dicts;
  final PhraseDictionary? hanVietFallback;

  const TranslationEngine({required this.dicts, this.hanVietFallback});

  List<Token> translate(String text,
      {TranslationMode mode = TranslationMode.japanese}) {
    final tokens = <Token>[];
    final n = text.length;
    var i = 0;
    var passStart = -1;

    void flushPassthrough(int end) {
      if (passStart >= 0) {
        tokens.add(Token(
          source: text.substring(passStart, end),
          sourceStart: passStart,
          kind: TokenKind.passthrough,
        ));
        passStart = -1;
      }
    }

    while (i < n) {
      final runeLen = runeLengthAt(text, i);
      final cp = codePointAt(text, i);

      if (!isCjkCodePoint(cp)) {
        if (passStart < 0) passStart = i;
        i += runeLen;
        continue;
      }
      flushPassthrough(i);

      // Độ dài thử tối đa: max của maxLenFor(code unit đầu) trên mọi dict.
      final firstUnit = text.codeUnitAt(i);
      var maxTry = 0;
      for (final dict in dicts) {
        final len = dict.maxLenFor(firstUnit);
        if (len > maxTry) maxTry = len;
      }
      if (maxTry > n - i) maxTry = n - i;

      var matched = false;
      for (var len = maxTry; len >= 1 && !matched; len--) {
        final candidate = text.substring(i, i + len);
        for (final dict in dicts) {
          final value = dict.entries[candidate];
          if (value != null) {
            tokens.add(Token(
              source: candidate,
              sourceStart: i,
              kind: TokenKind.matched,
              dictType: dict.type,
              meaning: firstMeaning(value),
            ));
            i += len;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;

      // Không match: chữ Hán đơn → phiên âm Hán Việt; kana/khác → giữ nguyên.
      final single = text.substring(i, i + runeLen);
      final fallbackValue =
          isHanCodePoint(cp) ? hanVietFallback?.entries[single] : null;
      if (fallbackValue != null) {
        tokens.add(Token(
          source: single,
          sourceStart: i,
          kind: TokenKind.hanViet,
          dictType: hanVietFallback!.type,
          meaning: firstMeaning(fallbackValue),
        ));
      } else {
        tokens.add(Token(
          source: single,
          sourceStart: i,
          kind: TokenKind.unmatched,
        ));
      }
      i += runeLen;
    }
    flushPassthrough(n);
    return tokens;
  }

  /// Nghĩa đầu tiên của value `nghĩa1/nghĩa2/...`.
  static String firstMeaning(String value) {
    final slash = value.indexOf('/');
    final first = slash < 0 ? value : value.substring(0, slash);
    return first.trim();
  }
}
