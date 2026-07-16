import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';

void main() {
  group('parseEntries', () {
    test('strips UTF-8 BOM before first key', () {
      final entries = parseEntries('﻿覚悟=giác ngộ\n');
      expect(entries['覚悟'], 'giác ngộ');
      expect(entries.containsKey('﻿覚悟'), isFalse);
    });

    test('accepts CRLF and LF line endings', () {
      final entries = parseEntries('一=nhất\r\n二=nhị\n三=tam');
      expect(entries, {'一': 'nhất', '二': 'nhị', '三': 'tam'});
    });

    test('splits at first = only, keeps = inside value', () {
      final entries = parseEntries('数式=công thức: a=b+c\n');
      expect(entries['数式'], 'công thức: a=b+c');
    });

    test('skips lines without = and empty lines', () {
      final entries = parseEntries('ghi chú không hợp lệ\n\n一=nhất\n');
      expect(entries.length, 1);
      expect(entries['一'], 'nhất');
    });

    test('skips lines with empty key (= at column 0)', () {
      final entries = parseEntries('=giá trị mồ côi\n一=nhất\n');
      expect(entries.length, 1);
    });

    test('duplicate keys keep first occurrence', () {
      final entries = parseEntries('一=nhất\n一=một\n');
      expect(entries['一'], 'nhất');
    });
  });

  group('parseDictionary index', () {
    test('maxLenByFirstUnit tracks longest key per first code unit', () {
      final dict = parseDictionary('覚=giác\n覚悟=giác ngộ\n持ち歩=mang theo\n',
          DictType.vietPhrase);
      expect(dict.maxLenFor('覚'.codeUnitAt(0)), 2);
      expect(dict.maxLenFor('持'.codeUnitAt(0)), 3);
      expect(dict.maxLenFor('無'.codeUnitAt(0)), 0);
    });
  });
}
