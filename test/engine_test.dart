import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

PhraseDictionary dict(DictType type, Map<String, String> entries) =>
    PhraseDictionary(type, entries);

void main() {
  group('TranslationEngine', () {
    test('greedy longest-match wins over shorter entries', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.vietPhrase, {
          '覚': 'giác',
          '覚悟': 'giác ngộ/quyết tâm',
        }),
      ]);
      final tokens = engine.translate('覚悟');
      expect(tokens, hasLength(1));
      expect(tokens.first.source, '覚悟');
      expect(tokens.first.meaning, 'giác ngộ');
      expect(tokens.first.kind, TokenKind.matched);
    });

    test('same length: Names beats VietPhrase (dict order priority)', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.names, {'田中': 'Tanaka'}),
        dict(DictType.vietPhrase, {'田中': 'điền trung'}),
      ]);
      final tokens = engine.translate('田中');
      expect(tokens.single.meaning, 'Tanaka');
      expect(tokens.single.dictType, DictType.names);
    });

    test('longer VietPhrase match beats shorter Names match', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.names, {'田中': 'Tanaka'}),
        dict(DictType.vietPhrase, {'田中さん': 'anh Tanaka'}),
      ]);
      final tokens = engine.translate('田中さん');
      expect(tokens.single.meaning, 'anh Tanaka');
    });

    test('unmatched single Han falls back to ChinesePhienAmWords', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'一番': 'nhất'}),
        ],
        hanVietFallback: dict(DictType.chinesePhienAm, {'第': 'đệ'}),
      );
      final tokens = engine.translate('第');
      expect(tokens.single.kind, TokenKind.hanViet);
      expect(tokens.single.meaning, 'đệ');
    });

    test('kana without match is kept as-is (unmatched)', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
        ],
        hanVietFallback: dict(DictType.chinesePhienAm, {'覚': 'giác'}),
      );
      final tokens = engine.translate('の');
      expect(tokens.single.kind, TokenKind.unmatched);
      expect(tokens.single.source, 'の');
      expect(tokens.single.display, 'の');
    });

    test('non-CJK runs are grouped into one passthrough token', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
      ]);
      final tokens = engine.translate('ABC 123, 覚悟!');
      expect(tokens, hasLength(3));
      expect(tokens[0].kind, TokenKind.passthrough);
      expect(tokens[0].source, 'ABC 123, ');
      expect(tokens[1].meaning, 'giác ngộ');
      expect(tokens[2].source, '!');
    });

    test('meaning is first sense trimmed, = in value preserved', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.vietPhrase, {'数式': ' a=b+c / nghĩa hai'.trim()}),
      ]);
      final tokens = engine.translate('数式');
      expect(tokens.single.meaning, 'a=b+c');
    });

    test('sourceStart is UTF-16 offset', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
      ]);
      final tokens = engine.translate('AB覚悟');
      expect(tokens[1].sourceStart, 2);
    });

    test('surrogate pair (non-CJK ext plane) advances by rune', () {
      final engine = TranslationEngine(dicts: [
        dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
      ]);
      // 𝄞 U+1D11E là surrogate pair ngoài CJK → passthrough nguyên rune.
      final tokens = engine.translate('𝄞覚悟');
      expect(tokens.first.source, '𝄞');
      expect(tokens[1].source, '覚悟');
    });

    test('repetition mark 々 and 〇 are treated as Han', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'人々': 'mọi người'}),
        ],
      );
      final tokens = engine.translate('人々');
      expect(tokens.single.meaning, 'mọi người');
    });
  });
}
