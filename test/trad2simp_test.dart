import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_loader.dart';
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

    test('không có cặp ngược chiều (giản → phồn)', () async {
      final table = Trad2SimpTable.parse(
        await rootBundle.loadString('assets/mappings/trad2simp.tsv'),
      );
      // Vài mục cedict bị đảo cột từng sinh ra `尔→爾`, khiến bản dịch Trung
      // biến 席尔 thành 席爾 rồi tra nhầm mục phồn thể.
      expect(table.convert('席尔'), '席尔');
      expect(table.convert('席爾'), '席尔');
      // Quy hai lần phải ra cùng kết quả. Cặp ngược chiều (`尔→爾`) hay chuỗi
      // (`託→托` mà `托→度`) đều làm kết quả dao động.
      const samples = [
        '尔', '脚', '于', '着', '周', '胜', '學而時習之',
        '託', '麼', '麽', '衚', '鬍', '辛', '緬', '胡', '托', '么',
      ];
      for (final sample in samples) {
        final once = table.convert(sample);
        expect(table.convert(once), once, reason: sample);
      }
    });
  });

  group('normalizeKeysToSimplified', () {
    // 爾→尔, 學→学, 麵→面, 面→面 (không đổi)
    final table = Trad2SimpTable.parse('爾\t尔\n學\t学\n麵\t面\n');

    test('key phồn thể chưa có bản giản thể thì được quy về giản thể', () {
      final entries = {'席爾': 'Sydney', '普通': 'phổ thông'};
      normalizeKeysToSimplified(entries, table);
      expect(entries, {'席尔': 'Sydney', '普通': 'phổ thông'});
    });

    test('key giản thể có sẵn thắng, không bị mục phồn thể ghi đè', () {
      final entries = {'席尔': 'đúng', '席爾': 'sai'};
      normalizeKeysToSimplified(entries, table);
      expect(entries, {'席尔': 'đúng'});
    });

    test('hai key phồn thể quy về cùng key: giữ mục xuất hiện trước', () {
      final entries = {'麵條': 'mì sợi', '麵条': 'mì sợi 2'};
      normalizeKeysToSimplified(entries, table);
      expect(entries.keys.toList(), ['面條', '面条']);
      final collide = {'學麵': 'a', '学麵': 'b'};
      normalizeKeysToSimplified(collide, table);
      expect(collide, {'学面': 'a'});
    });

    test('không có key phồn thể thì map giữ nguyên', () {
      final entries = {'普通': 'phổ thông', '面包': 'bánh mì'};
      normalizeKeysToSimplified(entries, table);
      expect(entries, {'普通': 'phổ thông', '面包': 'bánh mì'});
    });

    test('bảng rỗng là no-op', () {
      final entries = {'席爾': 'Sydney'};
      normalizeKeysToSimplified(entries, Trad2SimpTable.empty);
      expect(entries, {'席爾': 'Sydney'});
    });

    test('signature ổn định theo nội dung bảng, đổi khi bảng đổi', () {
      expect(Trad2SimpTable.parse('爾\t尔\n學\t学\n').signature,
          Trad2SimpTable.parse('學\t学\n爾\t尔\n').signature);
      expect(Trad2SimpTable.parse('爾\t尔\n').signature,
          isNot(Trad2SimpTable.parse('爾\t尔\n學\t学\n').signature));
      expect(Trad2SimpTable.empty.signature, isNotEmpty);
    });
  });
}
