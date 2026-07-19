import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/cjk.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';

/// Chốt chặn dữ liệu sinh bởi tool/build_sudachi_assets.dart — bug してくれ:
/// biến thể thuần hiragana (し=四, く=九...) khiến engine greedy match kana
/// đơn giữa chuỗi ngữ pháp. Skip khi thiếu file (chưa chạy tool).
void main() {
  test('SudachiVariants.txt: key phải chứa Hán hoặc thuần katakana ≥2', () {
    final file = File('data/jp/SudachiVariants.txt');
    if (!file.existsSync()) {
      markTestSkipped('Thiếu data/jp/SudachiVariants.txt');
      return;
    }
    final entries = parseEntries(
      const Utf8Codec(allowMalformed: true).decode(file.readAsBytesSync()),
    );
    expect(entries, isNotEmpty);

    bool hasHan(String s) {
      for (var i = 0; i < s.length; i += runeLengthAt(s, i)) {
        if (isHanCodePoint(codePointAt(s, i))) return true;
      }
      return false;
    }

    bool allKatakana(String s) {
      for (var i = 0; i < s.length; i += runeLengthAt(s, i)) {
        if (charCategoryOf(codePointAt(s, i)) != CjkCharCategory.katakana) {
          return false;
        }
      }
      return true;
    }

    final bad = entries.keys
        .where((k) => !hasHan(k) && !(k.length >= 2 && allKatakana(k)))
        .take(10)
        .toList();
    expect(bad, isEmpty, reason: 'Key không an toàn cho greedy match: $bad');
    expect(entries.containsKey('し'), isFalse);
    expect(entries.containsKey('く'), isFalse);
  });
}
