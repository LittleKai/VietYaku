import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/domain/japanese_variant_index.dart';

void main() {
  group('JapaneseVariantIndex.expandEntries', () {
    test('mở rộng một hình thái sang các cách viết kanji/kana', () {
      final index = JapaneseVariantIndex([
        ['吞み込ま', '吞みこま', 'のみこま', '呑み込ま', '飲み込ま'],
      ]);

      final expanded = index.expandEntries({'吞み込ま': 'nuốt chửng'});

      expect(expanded['吞み込ま'], 'nuốt chửng');
      expect(expanded['吞みこま'], 'nuốt chửng');
      expect(expanded['のみこま'], 'nuốt chửng');
      expect(expanded['呑み込ま'], 'nuốt chửng');
    });

    test('entry dạng thân từ bắt được nhóm nhờ cắt đuôi kana chung', () {
      // Sudachi chỉ có thể chia đầy đủ; entry người dùng là `吞み込`.
      final index = JapaneseVariantIndex([
        ['吞み込ま', '吞みこま', 'のみこま', '呑み込ま', '飲み込ま'],
      ]);

      final expanded = index.expandEntries({'吞み込': 'nuốt chửng'});

      expect(expanded['吞みこ'], 'nuốt chửng');
      expect(expanded['呑み込'], 'nuốt chửng');
      expect(expanded['飲み込'], 'nuốt chửng');
    });

    test('ghép biến thể của nhiều thành phần trong một cụm', () {
      final index = JapaneseVariantIndex([
        ['扱い', 'あつかい'],
        ['切れ', 'きれ', '斬れ'],
      ]);

      final expanded = index.expandEntries({'扱い切れ': 'xử lý được'});

      expect(expanded['扱いきれ'], 'xử lý được');
      expect(expanded['あつかいきれ'], 'xử lý được');
      expect(expanded['あつかい切れ'], 'xử lý được');
    });

    test('không đổi kanji sang kanji ở mảnh phụ', () {
      // `切れ` và `斬れ` chung dạng chuẩn + cách đọc nên cùng nhóm Sudachi,
      // nhưng `扱い斬れ` là từ khác nghĩa.
      final index = JapaneseVariantIndex([
        ['扱い', 'あつかい'],
        ['切れ', 'きれ', '斬れ'],
      ]);

      final expanded = index.expandEntries({'扱い切れ': 'xử lý được'});

      expect(expanded, isNot(contains('扱い斬れ')));
      expect(expanded, isNot(contains('あつかい斬れ')));
    });

    test('không dựng kanji từ mảnh kana khi phải ghép mảnh', () {
      // Một cách đọc ứng với nhiều kanji → đoán ngược dễ sinh từ khác nghĩa.
      final index = JapaneseVariantIndex([
        ['扱い', 'あつかい'],
        ['切れ', 'きれ', '斬れ'],
      ]);

      final expanded = index.expandEntries({'扱いきれ': 'xử lý được'});

      expect(expanded['あつかいきれ'], 'xử lý được');
      expect(expanded, isNot(contains('扱い切れ')));
      expect(expanded, isNot(contains('扱い斬れ')));
    });

    test('entry ghi rõ luôn thắng alias sinh tự động', () {
      final index = JapaneseVariantIndex([
        ['扱い', 'あつかい'],
        ['切れ', 'きれ'],
      ]);

      final expanded = index.expandEntries({
        '扱い切れ': 'xử lý được',
        '扱いきれ': 'nghĩa tự nhập',
      });

      expect(expanded['扱いきれ'], 'nghĩa tự nhập');
    });

    test('key từ 3 đơn vị vẫn nhận bản kana 3 ký tự', () {
      final index = JapaneseVariantIndex([
        ['吞み込ま', '吞みこま', 'のみこま'],
      ]);

      final expanded = index.expandEntries({'吞み込': 'nuốt chửng'});

      expect(expanded['のみこ'], 'nuốt chửng');
    });

    test('key ngắn không sinh alias kana đụng hư từ', () {
      // Nhóm thân từ cho ra cặp `空` ↔ `から`, nhưng `から` là trợ từ.
      final index = JapaneseVariantIndex([
        ['空い', 'からい'],
      ]);

      final expanded = index.expandEntries({'空': 'trống'});

      expect(expanded, isNot(contains('から')));
    });

    test('loại alias thuần hiragana ngắn để không ăn nhầm ngữ pháp', () {
      final index = JapaneseVariantIndex([
        ['呉れ', 'くれ'],
      ]);

      final expanded = index.expandEntries({'呉れ': 'cho'});

      expect(expanded, containsPair('呉れ', 'cho'));
      expect(expanded, isNot(contains('くれ')));
    });

    test('giới hạn số alias sinh từ một entry', () {
      final index = JapaneseVariantIndex([
        ['第一語', 'だいいちご', 'ダイイチゴ', 'ダイイチご', 'だいイチゴ'],
        ['第二語', 'だいにご', 'ダイニゴ', 'ダイニご', 'だいニゴ'],
        ['第三語', 'だいさんご', 'ダイサンゴ', 'ダイサンご', 'だいサンゴ'],
        ['第四語', 'だいよんご', 'ダイヨンゴ', 'ダイヨンご', 'だいヨンゴ'],
      ]);

      final expanded = index.expandEntries({
        '第一語第二語第三語第四語': 'nghĩa',
      }, maxAliasesPerEntry: 64);

      expect(expanded.length, 65); // 64 alias + 1 entry gốc.
      expect(expanded['第一語第二語第三語第四語'], 'nghĩa');
    });
  });
}
