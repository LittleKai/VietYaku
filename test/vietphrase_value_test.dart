import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/vietphrase_value.dart';

import '../tool/normalize_vietphrase_values.dart';

void main() {
  group('parseVietPhraseValue', () {
    test(
      'dấu gạch chéo thường chỉ ngăn cách cách dịch trong cùng một tầng',
      () {
        final meanings = parseVietPhraseValue('xào xạc/sà sà/sàn sạt');

        expect(meanings, hasLength(1));
        expect(meanings.single.text, 'xào xạc/sà sà/sàn sạt');
        expect(meanings.single.alternatives, ['xào xạc', 'sà sà', 'sàn sạt']);
        expect(meanings.single.partOfSpeech, VietPhrasePartOfSpeech.none);
      },
    );

    test('marker số mở tầng nghĩa mới ở dạng đứng riêng hoặc dính liền', () {
      final meanings = parseVietPhraseValue(
        'một/một khác/(2)/hai/hai khác/(3)ba',
      );

      expect(meanings.map((meaning) => meaning.text), [
        'một/một khác',
        'hai/hai khác',
        'ba',
      ]);
    });

    test('marker từ loại phân loại và mở tầng mới sau tầng đã có nội dung', () {
      final meanings = parseVietPhraseValue(
        '(n)vui vẻ/khoái lạc/sung sướng/(v)thưởng thức/'
        '(adj)chờ mong/mong mỏi/háo hức',
      );

      expect(meanings.map((meaning) => meaning.text), [
        'vui vẻ/khoái lạc/sung sướng',
        'thưởng thức',
        'chờ mong/mong mỏi/háo hức',
      ]);
      expect(meanings.map((meaning) => meaning.partOfSpeech), [
        VietPhrasePartOfSpeech.noun,
        VietPhrasePartOfSpeech.verb,
        VietPhrasePartOfSpeech.adjective,
      ]);
    });

    test('marker từ loại sau marker số chỉ phân loại tầng đang chờ', () {
      final meanings = parseVietPhraseValue(
        'kéo rời/tách ra/kéo dài/(2)/(n)/thế hòa/huề/ngang điểm',
      );

      expect(meanings.map((meaning) => meaning.text), [
        'kéo rời/tách ra/kéo dài',
        'thế hòa/huề/ngang điểm',
      ]);
      expect(meanings.last.partOfSpeech, VietPhrasePartOfSpeech.noun);
    });

    test(
      'ngoặc không phải marker hỗ trợ được giữ như cách dịch bình thường',
      () {
        final meanings = parseVietPhraseValue('(baka) ngốc/(sound) âm thanh');

        expect(meanings, hasLength(1));
        expect(meanings.single.text, '(baka) ngốc/(sound) âm thanh');
        expect(meanings.single.partOfSpeech, VietPhrasePartOfSpeech.none);
      },
    );
  });

  test('encodeVietPhraseValue ghi marker đứng riêng theo một chuẩn', () {
    final encoded = encodeVietPhraseValue(const [
      VietPhraseMeaning(
        text: 'ký ức/hồi ức',
        partOfSpeech: VietPhrasePartOfSpeech.noun,
      ),
      VietPhraseMeaning(
        text: 'nhớ lại',
        partOfSpeech: VietPhrasePartOfSpeech.verb,
      ),
      VietPhraseMeaning(text: 'hồi tưởng'),
    ]);

    expect(encoded, '(n)/ký ức/hồi ức/(2)/(v)/nhớ lại/(3)/hồi tưởng');
  });

  group('normalizeVietPhraseValue', () {
    test('không tự đánh số các cách dịch cùng một tầng', () {
      const value = 'xào xạc/sà sà/sàn sạt';
      expect(normalizeVietPhraseValue(value), value);
    });

    test('đưa marker dính và marker thiếu dấu gạch về dạng đứng riêng', () {
      const legacy = '(n)ký ức/hồi ức/(2)(v)nhớ lại/(3)/(adj)đáng nhớ';
      const canonical = '(n)/ký ức/hồi ức/(2)/(v)/nhớ lại/(3)/(adj)/đáng nhớ';

      expect(normalizeVietPhraseValue(legacy), canonical);
      expect(normalizeVietPhraseValue(canonical), canonical);
    });

    test('thêm số tầng cho dữ liệu cũ chỉ dùng từ loại làm ranh giới', () {
      const legacy =
          '(n)vui vẻ/khoái lạc/(v)thưởng thức/(adj)chờ mong/mong mỏi';
      const canonical =
          '(n)/vui vẻ/khoái lạc/(2)/(v)/thưởng thức/'
          '(3)/(adj)/chờ mong/mong mỏi';

      expect(normalizeVietPhraseValue(legacy), canonical);
    });
  });

  test('normalize file giữ BOM, CRLF, key và có tính idempotent', () {
    const input =
        '\uFEFF語=xào xạc/sà sà/sàn sạt\r\n'
        '楽しみ=(n)vui vẻ/khoái lạc/(v)thưởng thức\r\n'
        '空=không\r\n';

    final result = normalizeVietPhraseDictionaryContent(input);

    expect(result.entries, 3);
    expect(result.changed, 1);
    expect(
      result.content,
      '\uFEFF語=xào xạc/sà sà/sàn sạt\r\n'
      '楽しみ=(n)/vui vẻ/khoái lạc/(2)/(v)/thưởng thức\r\n'
      '空=không\r\n',
    );
    expect(normalizeVietPhraseDictionaryContent(result.content).changed, 0);
  });

  test('Token lấy cách dịch đầu và phân biệt từ loại ở panel một nghĩa', () {
    const token = Token(
      source: '楽しみ',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: '(n)/vui vẻ/khoái lạc/(2)/(v)/thưởng thức',
    );

    expect(token.meaning, 'vui vẻ');
    expect(token.displayWithPartOfSpeech, '(n) vui vẻ');
    expect(token.displayAll, '[(n) vui vẻ/khoái lạc/(v) thưởng thức]');
  });

  test('đa cách dịch trong một tầng vẫn được bọc ngoặc ở panel đa nghĩa', () {
    const token = Token(
      source: 'さらさら',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: 'xào xạc/sà sà/sàn sạt',
    );

    expect(token.meaning, 'xào xạc');
    expect(token.displayAll, '[xào xạc/sà sà/sàn sạt]');
  });

  test('panel một nghĩa vẫn ẩn token có value rỗng', () {
    const token = Token(
      source: '了',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: '',
    );

    expect(token.display, '');
    expect(token.displayWithPartOfSpeech, '');
  });

  test('MultiMeaningDisplayMode helper: circledNumber & superscriptNumber', () {
    expect(circledNumber(1), '①');
    expect(circledNumber(2), '②');
    expect(circledNumber(10), '⑩');
    expect(circledNumber(21), '(21)');

    expect(superscriptNumber(2), '²');
    expect(superscriptNumber(3), '³');
    expect(superscriptNumber(12), '¹²');
  });

  test('allVietPhraseMeaningsClean gom đủ các nghĩa sạch từ các tầng', () {
    expect(
      allVietPhraseMeaningsClean('(n)/ký ức/hồi ức/(2)/(v)/nhớ lại'),
      'ký ức/hồi ức/nhớ lại',
    );
    expect(
      allVietPhraseMeaningsClean('vui vẻ/khoái lạc/thích thú'),
      'vui vẻ/khoái lạc/thích thú',
    );
    expect(
      allVietPhraseMeaningsClean('(v)/chạy bộ/chạy nhanh/(2)/cuộc đua'),
      'chạy bộ/chạy nhanh/cuộc đua',
    );
    expect(
      allVietPhraseMeaningsClean('Rimuru Tempest'),
      'Rimuru Tempest',
    );
  });

  test('MultiMeaningDisplayMode fromKey fallback an toàn', () {
    expect(
      MultiMeaningDisplayMode.fromKey('tieredNumbered'),
      MultiMeaningDisplayMode.tieredNumbered,
    );
    expect(
      MultiMeaningDisplayMode.fromKey('classic'),
      MultiMeaningDisplayMode.classic,
    );
    expect(
      MultiMeaningDisplayMode.fromKey('invalid'),
      MultiMeaningDisplayMode.visualHierarchy,
    );
  });

  test('convertVietPhraseToLacVietFormat chuyển đổi chuẩn xác sang Lạc Việt', () {
    expect(
      convertVietPhraseToLacVietFormat('(n)/ký ức/hồi ức/(2)/(v)/nhớ lại'),
      r'- (danh từ) ký ức; hồi ức\n- (động từ) nhớ lại',
    );
    expect(
      convertVietPhraseToLacVietFormat('(v)/bắt đầu/khởi hành'),
      '- (động từ) bắt đầu; khởi hành',
    );
    expect(
      convertVietPhraseToLacVietFormat('vui vẻ/khoái lạc/thích thú'),
      'vui vẻ; khoái lạc; thích thú',
    );
    expect(
      convertVietPhraseToLacVietFormat('cách 1/(2)/cách 2'),
      r'- cách 1\n- cách 2',
    );
    expect(
      convertVietPhraseToLacVietFormat('Rimuru Tempest'),
      'Rimuru Tempest',
    );
  });
}
