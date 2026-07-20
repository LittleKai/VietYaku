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
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚': 'giác', '覚悟': 'giác ngộ/quyết tâm'}),
        ],
      );
      final tokens = engine.translate('覚悟');
      expect(tokens, hasLength(1));
      expect(tokens.first.source, '覚悟');
      expect(tokens.first.meaning, 'giác ngộ');
      expect(tokens.first.kind, TokenKind.matched);
    });

    test('same length: Names beats VietPhrase (dict order priority)', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.names, {'田中': 'Tanaka'}),
          dict(DictType.vietPhrase, {'田中': 'điền trung'}),
        ],
      );
      final tokens = engine.translate('田中');
      expect(tokens.single.meaning, 'Tanaka');
      expect(tokens.single.dictType, DictType.names);
    });

    test('longer VietPhrase match beats shorter Names match', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.names, {'田中': 'Tanaka'}),
          dict(DictType.vietPhrase, {'田中さん': 'anh Tanaka'}),
        ],
      );
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
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
        ],
      );
      final tokens = engine.translate('ABC 123, 覚悟!');
      expect(tokens, hasLength(3));
      expect(tokens[0].kind, TokenKind.passthrough);
      expect(tokens[0].source, 'ABC 123, ');
      expect(tokens[1].meaning, 'giác ngộ');
      expect(tokens[2].source, '!');
    });

    test('meaning is first sense trimmed, = in value preserved', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'数式': ' a=b+c / nghĩa hai'.trim()}),
        ],
      );
      final tokens = engine.translate('数式');
      expect(tokens.single.meaning, 'a=b+c');
    });

    test('sourceStart is UTF-16 offset', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
        ],
      );
      final tokens = engine.translate('AB覚悟');
      expect(tokens[1].sourceStart, 2);
    });

    test('surrogate pair (non-CJK ext plane) advances by rune', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
        ],
      );
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

  group('Token rawValue / displayAll', () {
    test('đa nghĩa → rawValue giữ nguyên, displayAll có ngoặc', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚悟': 'giác ngộ/quyết tâm'}),
        ],
      );
      final token = engine.translate('覚悟').single;
      expect(token.rawValue, 'giác ngộ/quyết tâm');
      expect(token.meaning, 'giác ngộ');
      expect(token.displayAll, '[giác ngộ/quyết tâm]');
    });

    test('một nghĩa → displayAll không ngoặc', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'人々': ' mọi người '}),
        ],
      );
      final token = engine.translate('人々').single;
      expect(token.displayAll, 'mọi người');
    });

    test('passthrough/unmatched → displayAll = source', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'覚悟': 'giác ngộ'}),
        ],
      );
      final tokens = engine.translate('ABの');
      expect(tokens[0].displayAll, 'AB');
      expect(tokens[1].displayAll, 'の');
    });
  });

  group('TranslationAlgorithm.longestPhrase', () {
    // '一二' (2) chặn '二三四五' (4) ở trái→phải; global thì cụm dài thắng.
    final dicts = [
      dict(DictType.vietPhrase, {'一二': 'a', '二三四五': 'b'}),
    ];
    final fallback = dict(DictType.chinesePhienAm, {'一': 'nhất', '五': 'ngũ'});

    test('leftToRight: cụm trái ăn trước dù chặn cụm dài hơn', () {
      final engine = TranslationEngine(dicts: dicts, hanVietFallback: fallback);
      final tokens = engine.translate('一二三四五');
      expect(tokens.first.source, '一二');
      expect(tokens.first.meaning, 'a');
    });

    test('longestPhrase: cụm dài toàn văn thắng, khe trống fallback', () {
      final engine = TranslationEngine(
        dicts: dicts,
        hanVietFallback: fallback,
        algorithm: TranslationAlgorithm.longestPhrase,
      );
      final tokens = engine.translate('一二三四五');
      expect(tokens, hasLength(2));
      expect(tokens[0].kind, TokenKind.hanViet);
      expect(tokens[0].meaning, 'nhất');
      expect(tokens[1].source, '二三四五');
      expect(tokens[1].meaning, 'b');
    });

    test('cùng độ dài chồng lấn → cụm bên trái thắng', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'一二': 'trái', '二三': 'phải'}),
        ],
        algorithm: TranslationAlgorithm.longestPhrase,
      );
      final tokens = engine.translate('一二三');
      expect(tokens.first.meaning, 'trái');
    });

    test('longestPhrase4: cụm 3 ký tự không vào vòng global', () {
      // '二三四' chỉ dài 3 → không ưu tiên global, trái→phải giữ '一二'.
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'一二': 'a', '二三四': 'c'}),
        ],
        algorithm: TranslationAlgorithm.longestPhrase4,
      );
      final tokens = engine.translate('一二三四');
      expect(tokens.first.source, '一二');
      expect(tokens.first.meaning, 'a');
    });

    test('longestPhrase4: cụm 4 ký tự vào vòng global và thắng', () {
      final engine = TranslationEngine(
        dicts: dicts,
        hanVietFallback: fallback,
        algorithm: TranslationAlgorithm.longestPhrase4,
      );
      final tokens = engine.translate('一二三四五');
      expect(tokens[1].source, '二三四五');
      expect(tokens[1].meaning, 'b');
    });
  });

  group('prioritizeNames', () {
    test('off (mặc định): cụm VietPhrase dài hơn thắng Names', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.names, {'田中': 'Tanaka'}),
          dict(DictType.vietPhrase, {'田中さん': 'anh Tanaka'}),
        ],
      );
      expect(engine.translate('田中さん').single.meaning, 'anh Tanaka');
    });

    test('on: Names thắng cụm VietPhrase dài hơn tại cùng vị trí', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.names, {'田中': 'Tanaka'}),
          dict(DictType.vietPhrase, {'田中さん': 'anh Tanaka'}),
        ],
        prioritizeNames: true,
      );
      final tokens = engine.translate('田中さん');
      expect(tokens.first.meaning, 'Tanaka');
      expect(tokens.first.dictType, DictType.names);
    });

    test('on: UserDict vẫn thắng Names', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.userDict, {'田': 'ruộng'}),
          dict(DictType.names, {'田中': 'Tanaka'}),
        ],
        prioritizeNames: true,
      );
      final tokens = engine.translate('田中');
      expect(tokens.first.meaning, 'ruộng');
      expect(tokens.first.dictType, DictType.userDict);
    });
  });

  group('matchAt (click lại giữa 1 cụm đã ghép)', () {
    test('click đầu cụm → cả cụm', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'少女達': 'các thiếu nữ', '女達': 'các cô gái'}),
        ],
      );
      final match = engine.matchAt('少女達', 0);
      expect(match.source, '少女達');
      expect(match.meaning, 'các thiếu nữ');
    });

    test('click vào 女 giữa 少女達 → tra lại từ 女, bỏ qua 少', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'少女達': 'các thiếu nữ', '女達': 'các cô gái'}),
        ],
      );
      final match = engine.matchAt('少女達', 1);
      expect(match.source, '女達');
      expect(match.sourceStart, 1);
      expect(match.meaning, 'các cô gái');
    });

    test('click vào ký tự cuối, không match dài hơn → fallback 1 ký tự', () {
      final engine = TranslationEngine(
        dicts: [
          dict(DictType.vietPhrase, {'少女達': 'các thiếu nữ'}),
        ],
        hanVietFallback: dict(DictType.chinesePhienAm, {'達': 'đạt'}),
      );
      final match = engine.matchAt('少女達', 2);
      expect(match.source, '達');
      expect(match.kind, TokenKind.hanViet);
      expect(match.meaning, 'đạt');
    });
  });

  group('Hán Việt toàn văn (dicts rỗng + fallback)', () {
    test('per chữ Hán, kana unmatched, Latin passthrough', () {
      final engine = TranslationEngine(
        dicts: const [],
        hanVietFallback: dict(DictType.chinesePhienAm, {
          '覚': 'giác',
          '悟': 'ngộ',
        }),
      );
      final tokens = engine.translate('覚悟のA');
      expect(tokens, hasLength(4));
      expect(tokens[0].kind, TokenKind.hanViet);
      expect(tokens[0].meaning, 'giác');
      expect(tokens[1].meaning, 'ngộ');
      expect(tokens[2].kind, TokenKind.unmatched);
      expect(tokens[3].kind, TokenKind.passthrough);
      expect(tokens[3].source, 'A');
    });
  });
}
