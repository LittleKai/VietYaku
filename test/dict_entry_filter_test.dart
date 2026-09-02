import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/domain/dict_entry_filter.dart';

void main() {
  group('isWordLikeEntry', () {
    test('nhận từ và cụm từ', () {
      expect(isWordLikeEntry('チャラ'), isTrue);
      expect(isWordLikeEntry('再入荷'), isTrue);
      expect(isWordLikeEntry('立入禁止'), isTrue);
      expect(isWordLikeEntry('胸に空いた切なさ'), isTrue); // 8 rune
      expect(isWordLikeEntry('破釜沉舟'), isTrue);
    });

    test('loại cả câu / mệnh đề dài', () {
      // Chính ca đã làm hỏng bản dịch: mệnh đề 13 rune lọt vào VietPhrase.
      expect(isWordLikeEntry('この人こんなにチャラかった'), isFalse);
      expect(isWordLikeEntry('あいうえおかきくけこさし'), isFalse); // 12 rune
    });

    test('loại chuỗi có dấu câu', () {
      expect(isWordLikeEntry('すごい！'), isFalse);
      expect(isWordLikeEntry('こんにちは、'), isFalse);
      expect(isWordLikeEntry('「引用」'), isFalse);
      expect(isWordLikeEntry('やった。'), isFalse);
    });

    test('loại chuỗi có khoảng trắng hoặc rỗng', () {
      expect(isWordLikeEntry('再入 荷'), isFalse);
      expect(isWordLikeEntry('a\nb'), isFalse);
      expect(isWordLikeEntry('   '), isFalse);
      expect(isWordLikeEntry(''), isFalse);
    });

    test('đếm theo rune, không theo UTF-16 code unit', () {
      // 6 ký tự ngoài BMP = 12 code unit nhưng vẫn là 6 rune → hợp lệ.
      const emoji = '𠀋𠀋𠀋𠀋𠀋𠀋';
      expect(emoji.length, greaterThan(maxWordLikeRunes));
      expect(isWordLikeEntry(emoji), isTrue);
    });
  });

  group('shortMeaningOf', () {
    test('lấy dòng nghĩa đầu tiên của thân Mazii', () {
      const body =
          '再入 「さいにゅう」 (Hán: TÁI NHẬP)\n'
          '- (n, n-pref) sự vào lại\n'
          '- (n) nghĩa thứ hai';
      expect(shortMeaningOf(body), equals('(n, n-pref) sự vào lại'));
    });

    test('không có dòng gạch đầu dòng thì lấy dòng đầu không rỗng', () {
      const body = '\n\nnhập hàng lại\nchi tiết thêm';
      expect(shortMeaningOf(body), equals('nhập hàng lại'));
    });

    test('cắt bớt nghĩa quá dài', () {
      final body = '- ${'a' * 300}';
      expect(shortMeaningOf(body).length, equals(maxShortMeaningChars));
    });

    test('thân rỗng trả chuỗi rỗng', () {
      expect(shortMeaningOf(''), isEmpty);
      expect(shortMeaningOf('   \n  \n'), isEmpty);
    });

    test('bỏ qua dòng gạch đầu dòng rỗng', () {
      const body = 'headword\n-\n- nghĩa thật';
      expect(shortMeaningOf(body), equals('nghĩa thật'));
    });

    test('bỏ qua dòng nhãn nguồn khi đọc lại value đã lưu', () {
      const stored =
          '<<Mazii Online>>\n番号 「ばんごう」 (Hán: PHIÊN HÀO)\n- số hiệu';
      expect(shortMeaningOf(stored), equals('số hiệu'));
    });
  });

  group('meaningMatchesWord', () {
    // Nguồn online tra mờ: gõ 再入荷 trả về mục của 再入. Đọc thì người dùng tự
    // nhận ra lệch, nhưng promote vào VietPhrase là nhét bản dịch SAI.
    test('nhận khi headword đúng bằng từ đã tra', () {
      const body = '番号 「ばんごう」 (Hán: PHIÊN HÀO)\n- số hiệu';
      expect(meaningMatchesWord('番号', body), isTrue);
    });

    test('loại khi nguồn trả về headword khác', () {
      const body = '再入 「さいにゅう」 (Hán: TÁI NHẬP)\n- (n) sự vào lại';
      expect(meaningMatchesWord('再入荷', body), isFalse);
    });

    test('đọc được headword qua dòng nhãn nguồn', () {
      const stored = '<<Mazii Online>>\n機嫌 「きげん」\n- (n) tâm trạng';
      expect(meaningMatchesWord('機嫌', stored), isTrue);
    });

    test('không xác nhận được thì loại', () {
      expect(meaningMatchesWord('番号', ''), isFalse);
      expect(meaningMatchesWord('番号', '- chỉ có dòng nghĩa'), isFalse);
    });

    test('headwordOf cắt trước 「 và trước khoảng trắng', () {
      expect(headwordOf('番号 「ばんごう」 (Hán: PHIÊN HÀO)'), equals('番号'));
      expect(headwordOf('立入禁止 (thường dùng, N5)'), equals('立入禁止'));
      expect(headwordOf('複製'), equals('複製'));
    });
  });

  group('vietnameseLookupLabels', () {
    test('chỉ Mazii trả nghĩa tiếng Việt', () {
      expect(vietnameseLookupLabels, contains('Mazii Online'));
      // Jisho/Youdao trả tiếng Anh, Weblio trả tiếng Trung → không được vào
      // VietPhrase, nếu không bản dịch sẽ chen tiếng Anh/Trung giữa câu Việt.
      expect(vietnameseLookupLabels, isNot(contains('Jisho')));
      expect(vietnameseLookupLabels, isNot(contains('Youdao 中英')));
      expect(vietnameseLookupLabels, isNot(contains('Weblio 日中')));
      expect(vietnameseLookupLabels, isNot(contains('Google Dịch')));
    });
  });
}
