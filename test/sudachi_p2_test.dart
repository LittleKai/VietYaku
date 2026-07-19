import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/jp_input_normalizer.dart';
import 'package:vietyaku/features/translation/domain/kanji_numeral.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  group('normalizeJapaneseInput', () {
    test('halfwidth katakana → fullwidth, map offset 1-1', () {
      final r = normalizeJapaneseInput('ｱｲｳ');
      expect(r.text, 'アイウ');
      expect(r.changed, isTrue);
      expect(r.toOriginal, [0, 1, 2, 3]);
    });

    test('ghép dakuten 2 code unit gốc → 1 code unit chuẩn', () {
      final r = normalizeJapaneseInput('ｶﾞｹﾞ');
      expect(r.text, 'ガゲ');
      expect(r.toOriginal, [0, 2, 4]);
    });

    test('ｳﾞ → ヴ, ﾊﾟ → パ', () {
      expect(normalizeJapaneseInput('ｳﾞ').text, 'ヴ');
      expect(normalizeJapaneseInput('ﾊﾟ').text, 'パ');
    });

    test('dakuten không ghép được giữ nguyên rời', () {
      final r = normalizeJapaneseInput('ﾝﾞ');
      expect(r.text, 'ンﾞ'); // ン fullwidth + ﾞ giữ halfwidth
      expect(r.toOriginal, [0, 1, 2]);
    });

    test('văn bản trộn: chỉ đoạn halfwidth đổi, offset đúng', () {
      final r = normalizeJapaneseInput('あｶﾞx');
      expect(r.text, 'あガx');
      expect(r.toOriginal, [0, 1, 3, 4]);
    });

    test('không có halfwidth → changed=false, text giữ nguyên', () {
      final r = normalizeJapaneseInput('こんにちは。ABC');
      expect(r.changed, isFalse);
      expect(r.text, 'こんにちは。ABC');
    });
  });

  group('normalize + engine + remap', () {
    TranslationEngine engineWith(Map<String, String> entries) =>
        TranslationEngine(
          dicts: [PhraseDictionary(DictType.vietPhrase, entries)],
        );

    test('match key fullwidth trên input halfwidth, source/offset về gốc', () {
      const original = 'zｶﾞｹﾞz';
      final norm = normalizeJapaneseInput(original);
      final tokens = remapTokensToOriginal(
        engineWith({'ガゲ': 'v'}).translate(norm.text),
        original,
        norm.toOriginal,
      );
      final matched = tokens.singleWhere((t) => t.kind == TokenKind.matched);
      expect(matched.source, 'ｶﾞｹﾞ');
      expect(matched.sourceStart, 1);
      expect(matched.rawValue, 'v');
      expect(tokens.last.sourceStart, 5);
    });
  });

  group('parseKanjiNumber', () {
    test('kiểu vị trí', () {
      expect(parseKanjiNumber('三百二十五'), '325');
      expect(parseKanjiNumber('千九百八十四'), '1984');
      expect(parseKanjiNumber('一万二千'), '12000');
      expect(parseKanjiNumber('二億三千万'), '230000000');
      expect(parseKanjiNumber('十五'), '15');
      expect(parseKanjiNumber('十'), '10');
    });

    test('kiểu liệt kê chữ số', () {
      expect(parseKanjiNumber('一九八四'), '1984');
      expect(parseKanjiNumber('〇三'), '03');
    });

    test('không hợp lệ → null', () {
      expect(parseKanjiNumber('十百'), isNull);
      expect(parseKanjiNumber('一二百'), isNull);
      expect(parseKanjiNumber('万億'), isNull);
      expect(parseKanjiNumber('五x'), isNull);
      expect(parseKanjiNumber(''), isNull);
    });
  });

  group('joinKanjiNumerals', () {
    Token hanViet(String s, int start) => Token(
      source: s,
      sourceStart: start,
      kind: TokenKind.hanViet,
      dictType: DictType.chinesePhienAm,
      rawValue: 'x',
    );

    test('gộp run ≥2 token số liền kề thành 1 token số Ả Rập', () {
      final out = joinKanjiNumerals([
        hanViet('三', 0),
        hanViet('百', 1),
        const Token(source: 'あ', sourceStart: 2, kind: TokenKind.unmatched),
      ]);
      expect(out, hasLength(2));
      expect(out.first.source, '三百');
      expect(out.first.rawValue, '300');
      expect(out.first.kind, TokenKind.matched);
      expect(out.first.sourceStart, 0);
    });

    test('token đơn lẻ và token matched không bị đổi', () {
      final matched = Token(
        source: '一人',
        sourceStart: 0,
        kind: TokenKind.matched,
        dictType: DictType.vietPhrase,
        rawValue: 'một người',
      );
      final out = joinKanjiNumerals([matched, hanViet('五', 2)]);
      expect(out, [matched, out[1]]);
      expect(out[1].source, '五');
      expect(out[1].kind, TokenKind.hanViet);
    });

    test('run không liền kề (có khoảng cách offset) không gộp', () {
      final out = joinKanjiNumerals([hanViet('三', 0), hanViet('百', 5)]);
      expect(out, hasLength(2));
    });

    test('run parse thất bại giữ nguyên token gốc', () {
      final out = joinKanjiNumerals([hanViet('十', 0), hanViet('百', 1)]);
      expect(out, hasLength(2));
      expect(out[0].source, '十');
      expect(out[1].source, '百');
    });
  });
}
