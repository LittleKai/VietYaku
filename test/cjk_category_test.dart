import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/cjk.dart';

void main() {
  group('charCategoryOf', () {
    CjkCharCategory cat(String ch) => charCategoryOf(codePointAt(ch, 0));

    test('space: ASCII, tab, xuống dòng, fullwidth 0x3000', () {
      expect(cat(' '), CjkCharCategory.space);
      expect(cat('\t'), CjkCharCategory.space);
      expect(cat('\n'), CjkCharCategory.space);
      expect(cat('　'), CjkCharCategory.space);
    });

    test('numeric: ASCII + fullwidth', () {
      expect(cat('5'), CjkCharCategory.numeric);
      expect(cat('７'), CjkCharCategory.numeric);
    });

    test('alpha: ASCII, fullwidth, Latin-1, chữ Việt có dấu', () {
      expect(cat('a'), CjkCharCategory.alpha);
      expect(cat('Z'), CjkCharCategory.alpha);
      expect(cat('Ｂ'), CjkCharCategory.alpha);
      expect(cat('à'), CjkCharCategory.alpha);
      expect(cat('ế'), CjkCharCategory.alpha); // Latin Extended Additional
    });

    test('hiragana / katakana (gồm ー, kana nhỏ, halfwidth)', () {
      expect(cat('あ'), CjkCharCategory.hiragana);
      expect(cat('ア'), CjkCharCategory.katakana);
      expect(cat('ー'), CjkCharCategory.katakana);
      expect(cat('ㇰ'), CjkCharCategory.katakana);
      expect(cat('ｱ'), CjkCharCategory.katakana); // halfwidth
      expect(cat('ﾞ'), CjkCharCategory.katakana); // dakuten halfwidth
    });

    test('kanjiNumeric ưu tiên hơn kanji; vẫn là Hán theo isHanCodePoint', () {
      for (final ch in '〇一二三四五六七八九十百千万億兆'.split('')) {
        expect(cat(ch), CjkCharCategory.kanjiNumeric, reason: ch);
        expect(isHanCodePoint(codePointAt(ch, 0)), isTrue, reason: ch);
      }
    });

    test('kanji: chữ Hán thường + 々', () {
      expect(cat('漢'), CjkCharCategory.kanji);
      expect(cat('々'), CjkCharCategory.kanji);
    });

    test('other: dấu câu CJK, ký hiệu', () {
      expect(cat('。'), CjkCharCategory.other);
      expect(cat('・'), CjkCharCategory.other);
      expect(cat('！'), CjkCharCategory.other);
    });
  });

  group('isWordCodePoint & hasWordChar', () {
    test('chữ số ASCII và toàn-hình là word character', () {
      expect(hasWordChar('3'), isTrue);
      expect(hasWordChar('３'), isTrue);
      expect(hasWordChar('10'), isTrue);
      expect(hasWordChar('０'), isTrue);
    });

    test('chữ cái ASCII và toàn-hình là word character', () {
      expect(hasWordChar('A'), isTrue);
      expect(hasWordChar('ａ'), isTrue);
      expect(hasWordChar('Type-C'), isTrue);
    });

    test('CJK (kanji, kana) là word character', () {
      expect(hasWordChar('第'), isTrue);
      expect(hasWordChar('奥部'), isTrue);
      expect(hasWordChar('かな'), isTrue);
    });

    test('dấu câu và khoảng trắng thuần không phải word character', () {
      expect(hasWordChar('、'), isFalse);
      expect(hasWordChar('。'), isFalse);
      expect(hasWordChar('，'), isFalse);
      expect(hasWordChar('.'), isFalse);
      expect(hasWordChar('!'), isFalse);
      expect(hasWordChar(' '), isFalse);
      expect(hasWordChar('\t\n'), isFalse);
      expect(hasWordChar('……'), isFalse);
      expect(hasWordChar(''), isFalse);
    });
  });
}
