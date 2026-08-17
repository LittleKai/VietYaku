import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/domain/reading_extractor.dart';

void main() {
  group('extractReading (value LacViet thật)', () {
    test('romaji trong ngoặc tròn đầu value', () {
      final r = extractReading(
        '(kakugo)giác ngộ; quyết tâm; chuẩn bị tâm lý; chuẩn bị sẵn tinh thần',
      );
      expect(r?.text, 'kakugo');
      expect(r?.kind, ReadingKind.romaji);
    });

    test('pinyin sau ✚ đầu value', () {
      final r = extractReading(
        r'✚[fānyì] \n\t1. dịch; phiên dịch\n\t2. người dịch; phiên dịch viên',
      );
      expect(r?.text, 'fānyì');
      expect(r?.kind, ReadingKind.pinyin);
    });

    test('pinyin sau ✚ nằm giữa value (lấy nhóm đầu sau ✚)', () {
      final r = extractReading(
        r'\t-trở lại; twist back; return; khôi phục\n✚[lì] Hán Việt: LỆ\n\t1. tội lỗi',
      );
      expect(r?.text, 'lì');
      expect(r?.kind, ReadingKind.pinyin);
    });

    test('ngoặc vuông đầu value không có ✚', () {
      final r = extractReading('[líng] Hán Việt: LINH số không; zê-rô');
      expect(r?.text, 'líng');
      expect(r?.kind, ReadingKind.pinyin);
    });

    test('ngoặc tròn chứa tiếng Việt có dấu → không phải romaji → null', () {
      expect(extractReading('(cũ) nghĩa xưa của từ'), isNull);
    });

    test('value thường không có phiên âm → null (không đoán)', () {
      expect(
        extractReading('bá quyền (dùng sức mạnh để thao túng); chủ quyền'),
        isNull,
      );
    });
  });

  group('unescapeLacViet', () {
    test(r'literal \n\t đổi thành newline/tab thật', () {
      expect(
        unescapeLacViet(r'✚[fānyì] \n\t1. dịch;'),
        '✚[fānyì] \n\t1. dịch;',
      );
    });

    test('value không escape giữ nguyên', () {
      expect(unescapeLacViet('giác ngộ; quyết tâm'), 'giác ngộ; quyết tâm');
    });
  });

  group('escapeLacVietMeaning', () {
    test(r'newline/tab thật đổi lại thành literal \n\t', () {
      expect(
        escapeLacVietMeaning('\t- phí tổn\n\t- nhờ vào'),
        r'\t- phí tổn\n\t- nhờ vào',
      );
    });

    test('CRLF cũng thành một literal \\n', () {
      expect(escapeLacVietMeaning('a\r\nb'), r'a\nb');
    });

    test(r'dấu / ngăn cách nghĩa đổi thành "; "', () {
      expect(
        escapeLacVietMeaning('chiếm cứ/chiếm lấy/chiếm đóng'),
        'chiếm cứ; chiếm lấy; chiếm đóng',
      );
    });

    test('khoảng trắng quanh dấu / bị gộp vào "; "', () {
      expect(escapeLacVietMeaning('phản / trả lại'), 'phản; trả lại');
    });

    test('dấu / không nuốt xuống dòng liền kề', () {
      expect(escapeLacVietMeaning('a/\n\tb'), r'a; \n\tb');
    });

    test('round-trip: unescape rồi escape trả về đúng value gốc', () {
      const raw = r'\n\t1. dịch; phiên dịch\n\t2. người dịch';
      expect(escapeLacVietMeaning(unescapeLacViet(raw)), raw);
    });
  });
}
