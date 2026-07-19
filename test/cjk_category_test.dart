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

  group('categoryRunsOf', () {
    test('tách run cùng category, biên đúng theo code unit', () {
      final runs = categoryRunsOf('スーパー30台だ');
      expect(runs, [
        (start: 0, end: 4, category: CjkCharCategory.katakana),
        (start: 4, end: 6, category: CjkCharCategory.numeric),
        (start: 6, end: 7, category: CjkCharCategory.kanji),
        (start: 7, end: 8, category: CjkCharCategory.hiragana),
      ]);
    });

    test('surrogate pair không bị cắt đôi', () {
      // 𠮷 (U+20BB7, 2 code unit) ngoài các dải đã khai → other.
      final runs = categoryRunsOf('𠮷あ');
      expect(runs, [
        (start: 0, end: 2, category: CjkCharCategory.other),
        (start: 2, end: 3, category: CjkCharCategory.hiragana),
      ]);
    });

    test('chuỗi rỗng → không có run', () {
      expect(categoryRunsOf(''), isEmpty);
    });
  });
}
