import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/domain/trad2simp_table.dart';

void main() {
  const tsv = '# comment\n時\t时\n間\t间\n說\t说\n';

  group('Trad2SimpTable.parse', () {
    test('quy từng ký tự phồn thể, ký tự khác giữ nguyên', () {
      final table = Trad2SimpTable.parse(tsv);
      expect(table.convert('時間'), '时间');
      expect(table.convert('他說時間到了'), '他说时间到了');
    });

    test('không có ký tự phồn thể → trả về đúng chuỗi cũ', () {
      final table = Trad2SimpTable.parse(tsv);
      const text = '你好，世界！';
      expect(identical(table.convert(text), text), isTrue);
    });

    test('bảng rỗng là passthrough', () {
      expect(Trad2SimpTable.empty.convert('時間'), '時間');
      expect(Trad2SimpTable.empty.isEmpty, isTrue);
    });

    test('bỏ dòng comment và dòng hỏng', () {
      final table = Trad2SimpTable.parse('# x\nsai dòng\n時\t时\n');
      expect(table.convert('時'), '时');
    });
  });

  group('assets/mappings/trad2simp.tsv', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('giữ nguyên độ dài UTF-16 (offset token phải còn khớp)', () async {
      final table = Trad2SimpTable.parse(
        await rootBundle.loadString('assets/mappings/trad2simp.tsv'),
      );
      expect(table.isEmpty, isFalse);
      // Nếu bảng có cặp lệch độ dài thì token sẽ trỏ sai offset ô Nguồn.
      const samples = [
        '時間',
        '他說國語',
        '電車發車',
        '你好世界', // vốn đã là giản thể
      ];
      for (final sample in samples) {
        expect(table.convert(sample).length, sample.length, reason: sample);
      }
      expect(table.convert('時間'), '时间');
      expect(table.convert('他說國語'), '他说国语');
      expect(table.convert('你好世界'), '你好世界');
    });
  });
}
