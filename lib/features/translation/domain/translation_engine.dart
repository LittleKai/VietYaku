import '../../../core/cjk.dart';
import '../../dictionary/domain/dict_type.dart';
import '../../dictionary/domain/phrase_dictionary.dart';
import 'token.dart';

enum TranslationMode { japanese, chinese }

/// Thuật toán chọn cụm khi dịch.
enum TranslationAlgorithm {
  /// Quét trái→phải, tại mỗi vị trí lấy match dài nhất (mặc định).
  leftToRight,

  /// Ưu tiên cụm dài toàn văn bản: cụm dài nhất được đặt trước (không chồng
  /// lấn), khe trống còn lại dịch trái→phải.
  longestPhrase,

  /// Như [longestPhrase] nhưng chỉ cụm ≥ 4 code unit vào vòng ưu tiên toàn
  /// văn; cụm ngắn hơn dịch trái→phải trong khe trống.
  longestPhrase4,
}

typedef _Match = ({int len, DictType dictType, String value});

/// Engine dịch greedy longest-match theo UTF-16 code unit.
///
/// [dicts] theo thứ tự ưu tiên (UserDict > Names > VietPhrase): cùng độ dài
/// match thì dict đứng trước thắng. [hanVietFallback] là ChinesePhienAmWords
/// cho chữ Hán đơn không match. Chữ ký translate() giữ ổn định để v2 cắm
/// AiTranslationEngine cùng interface.
///
/// [prioritizeNames] = true: mỗi dict là một bậc ưu tiên — dict đứng trước có
/// match (bất kỳ độ dài) thì thắng dict sau dù dict sau match dài hơn.
class TranslationEngine {
  final List<PhraseDictionary> dicts;
  final PhraseDictionary? hanVietFallback;
  final TranslationAlgorithm algorithm;
  final bool prioritizeNames;

  const TranslationEngine({
    required this.dicts,
    this.hanVietFallback,
    this.algorithm = TranslationAlgorithm.leftToRight,
    this.prioritizeNames = false,
  });

  List<Token> translate(
    String text, {
    TranslationMode mode = TranslationMode.japanese,
  }) {
    switch (algorithm) {
      case TranslationAlgorithm.leftToRight:
        return _translateLeftToRight(text);
      case TranslationAlgorithm.longestPhrase:
        return _translateGlobal(text, 1);
      case TranslationAlgorithm.longestPhrase4:
        return _translateGlobal(text, 4);
    }
  }

  /// Match dài nhất tại [i], key kết thúc không vượt quá [limitEnd].
  _Match? _longestMatchAt(String text, int i, int limitEnd) {
    final firstUnit = text.codeUnitAt(i);
    if (prioritizeNames) {
      for (final dict in dicts) {
        var maxTry = dict.maxLenFor(firstUnit);
        if (maxTry > limitEnd - i) maxTry = limitEnd - i;
        for (var len = maxTry; len >= 1; len--) {
          final value = dict.entries[text.substring(i, i + len)];
          if (value != null) {
            return (len: len, dictType: dict.type, value: value);
          }
        }
      }
      return null;
    }
    var maxTry = 0;
    for (final dict in dicts) {
      final len = dict.maxLenFor(firstUnit);
      if (len > maxTry) maxTry = len;
    }
    if (maxTry > limitEnd - i) maxTry = limitEnd - i;
    for (var len = maxTry; len >= 1; len--) {
      final candidate = text.substring(i, i + len);
      for (final dict in dicts) {
        final value = dict.entries[candidate];
        if (value != null) {
          return (len: len, dictType: dict.type, value: value);
        }
      }
    }
    return null;
  }

  /// Chữ Hán đơn → phiên âm Hán Việt; kana/khác → giữ nguyên.
  Token _fallbackToken(String text, int i, int runeLen, int cp) {
    final single = text.substring(i, i + runeLen);
    final fallbackValue = isHanCodePoint(cp)
        ? hanVietFallback?.entries[single]
        : null;
    if (fallbackValue != null) {
      return Token(
        source: single,
        sourceStart: i,
        kind: TokenKind.hanViet,
        dictType: hanVietFallback!.type,
        rawValue: fallbackValue,
      );
    }
    return Token(source: single, sourceStart: i, kind: TokenKind.unmatched);
  }

  List<Token> _translateLeftToRight(String text) {
    final tokens = <Token>[];
    final n = text.length;
    var i = 0;
    var passStart = -1;

    void flushPassthrough(int end) {
      if (passStart >= 0) {
        tokens.add(
          Token(
            source: text.substring(passStart, end),
            sourceStart: passStart,
            kind: TokenKind.passthrough,
          ),
        );
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

      final match = _longestMatchAt(text, i, n);
      if (match != null) {
        tokens.add(
          Token(
            source: text.substring(i, i + match.len),
            sourceStart: i,
            kind: TokenKind.matched,
            dictType: match.dictType,
            rawValue: match.value,
          ),
        );
        i += match.len;
        continue;
      }

      tokens.add(_fallbackToken(text, i, runeLen, cp));
      i += runeLen;
    }
    flushPassthrough(n);
    return tokens;
  }

  /// Ưu tiên cụm dài toàn văn: cụm ≥ [minGlobalLen] đặt trước theo
  /// (dài hơn trước, trái hơn trước), khe trống dịch trái→phải bị chặn biên.
  List<Token> _translateGlobal(String text, int minGlobalLen) {
    final n = text.length;

    // Pass 1: match dài nhất tại mỗi vị trí CJK.
    final candidates = <({int start, _Match match})>[];
    {
      var i = 0;
      while (i < n) {
        final runeLen = runeLengthAt(text, i);
        if (isCjkCodePoint(codePointAt(text, i))) {
          final m = _longestMatchAt(text, i, n);
          if (m != null && m.len >= minGlobalLen) {
            candidates.add((start: i, match: m));
          }
        }
        i += runeLen;
      }
    }

    // Pass 2: đặt cụm dài trước, không chồng lấn; cùng độ dài → trái thắng.
    candidates.sort(
      (a, b) => a.match.len != b.match.len
          ? b.match.len - a.match.len
          : a.start - b.start,
    );
    final occupied = List<bool>.filled(n, false);
    final placed = <int, _Match>{};
    for (final c in candidates) {
      final end = c.start + c.match.len;
      var free = true;
      for (var j = c.start; j < end && free; j++) {
        if (occupied[j]) free = false;
      }
      if (!free) continue;
      for (var j = c.start; j < end; j++) {
        occupied[j] = true;
      }
      placed[c.start] = c.match;
    }

    // Pass 3: lắp ráp trái→phải; khe trống dịch greedy không vượt biên
    // cụm đã đặt. [boundary] tiến đơn điệu → O(n).
    final tokens = <Token>[];
    var passStart = -1;

    void flushPassthrough(int end) {
      if (passStart >= 0) {
        tokens.add(
          Token(
            source: text.substring(passStart, end),
            sourceStart: passStart,
            kind: TokenKind.passthrough,
          ),
        );
        passStart = -1;
      }
    }

    var i = 0;
    var boundary = 0;
    while (i < n) {
      final placedMatch = placed[i];
      if (placedMatch != null) {
        flushPassthrough(i);
        tokens.add(
          Token(
            source: text.substring(i, i + placedMatch.len),
            sourceStart: i,
            kind: TokenKind.matched,
            dictType: placedMatch.dictType,
            rawValue: placedMatch.value,
          ),
        );
        i += placedMatch.len;
        continue;
      }

      final runeLen = runeLengthAt(text, i);
      final cp = codePointAt(text, i);
      if (!isCjkCodePoint(cp)) {
        if (passStart < 0) passStart = i;
        i += runeLen;
        continue;
      }
      flushPassthrough(i);

      if (boundary < i) boundary = i;
      while (boundary < n && !occupied[boundary]) {
        boundary++;
      }
      final match = boundary > i ? _longestMatchAt(text, i, boundary) : null;
      if (match != null) {
        tokens.add(
          Token(
            source: text.substring(i, i + match.len),
            sourceStart: i,
            kind: TokenKind.matched,
            dictType: match.dictType,
            rawValue: match.value,
          ),
        );
        i += match.len;
        continue;
      }

      tokens.add(_fallbackToken(text, i, runeLen, cp));
      i += runeLen;
    }
    flushPassthrough(n);
    return tokens;
  }
}
