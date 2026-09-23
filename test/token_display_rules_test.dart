import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/cjk.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/domain/vietphrase_value.dart';
import 'package:vietyaku/features/translation/presentation/token_text_view.dart';

void main() {
  group('normalizeDisplayText — ngoặc kép CJK', () {
    test('「」｢｣ luôn thành "', () {
      expect(normalizeDisplayText('「あ」'), '"あ"');
      expect(normalizeDisplayText('｢あ｣'), '"あ"');
    });

    test('mặc định giữ nguyên 『』《》〈〉〝〟', () {
      expect(normalizeDisplayText('『あ』'), '『あ』');
      expect(normalizeDisplayText('《あ》'), '《あ》');
      expect(normalizeDisplayText('〈あ〉'), '〈あ〉');
      expect(normalizeDisplayText('〝あ〟'), '〝あ〟');
    });

    test('tắt keepSpecialQuotes → chuyển thành "', () {
      expect(normalizeDisplayText('『あ』', keepSpecialQuotes: false), '"あ"');
      expect(normalizeDisplayText('《あ》', keepSpecialQuotes: false), '"あ"');
    });
  });

  group('displayAllWith — ngoặc vuông cụm 1 nghĩa', () {
    const single = Token(
      source: '行',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: 'hành',
    );
    const multi = Token(
      source: '行',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: 'hành/đi',
    );

    test('mặc định (tắt): 1 nghĩa không ngoặc', () {
      expect(single.displayAll, 'hành');
      expect(multi.displayAll, '[hành/đi]');
    });

    test('bật: 1 nghĩa cũng bọc ngoặc', () {
      expect(single.displayAllWith(bracketSingle: true), '[hành]');
      expect(multi.displayAllWith(bracketSingle: true), '[hành/đi]');
    });
  });

  group('viết hoa sau nháy/ngoặc mở', () {
    test('『 đầu hàng (giữ nguyên) → 『[Hành/đi]', () {
      final tokens = [
        const Token(source: '『', sourceStart: 0, kind: TokenKind.passthrough),
        const Token(
          source: '行',
          sourceStart: 1,
          kind: TokenKind.matched,
          rawValue: 'hành/đi',
        ),
      ];
      final out = TokenTextView.plainText(
        tokens,
        (t) => t.displayAllWith(bracketSingle: true),
      );
      expect(out, '『[Hành/đi]');
      expect(
        TokenTextView.plainText(
          tokens,
          (t) => t.displayAllWith(bracketSingle: true),
          keepSpecialQuotes: false,
        ),
        '" [Hành/đi]',
      );
    });

    test('nháy giữa câu không viết hoa; sau 。" thì viết hoa', () {
      final tokens = [
        const Token(
          source: '言',
          sourceStart: 0,
          kind: TokenKind.matched,
          rawValue: 'nói:',
        ),
        const Token(source: '「', sourceStart: 1, kind: TokenKind.passthrough),
        const Token(
          source: '行',
          sourceStart: 2,
          kind: TokenKind.matched,
          rawValue: 'đi thôi',
        ),
        const Token(source: '。」', sourceStart: 3, kind: TokenKind.passthrough),
        const Token(
          source: '彼',
          sourceStart: 5,
          kind: TokenKind.matched,
          rawValue: 'hắn',
        ),
      ];
      final out = TokenTextView.plainText(tokens, (t) => t.display);
      expect(out, 'Nói: " đi thôi. " Hắn');
    });
    test('từ đa nghĩa có từ loại ở đầu dòng viết hoa đúng từ chứ không viết hoa nhãn (n)', () {
      final tokens = [
        const Token(
          source: '記憶',
          sourceStart: 0,
          kind: TokenKind.matched,
          rawValue: '(n)/ký ức/hồi ức/(2)/(v)/nhớ lại',
        ),
      ];
      final out = TokenTextView.plainText(
        tokens,
        (t) => t.displayAllWith(),
      );
      expect(out, '[(n) Ký ức/hồi ức/(v) nhớ lại]');
    });
  });

  group('selectionSourceKey — key của vùng bôi đen ở ô kết quả', () {
    // 激出了火气: 了 có value rỗng (`了=` trong VietPhrase) nên không hiển thị,
    // vùng chọn chỉ chứa 激出 và 火气.
    const jiChu = Token(
      source: '激出',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: 'kích động ra',
    );
    const le = Token(
      source: '了',
      sourceStart: 2,
      kind: TokenKind.matched,
      rawValue: '',
    );
    const huoQi = Token(
      source: '火气',
      sourceStart: 3,
      kind: TokenKind.matched,
      rawValue: 'hỏa khí',
    );
    const after = Token(
      source: '他',
      sourceStart: 5,
      kind: TokenKind.matched,
      rawValue: 'hắn',
    );
    const paragraph = [jiChu, le, huoQi, after];

    test('token nghĩa rỗng nằm giữa vẫn vào key', () {
      expect(selectionSourceKey(paragraph, [jiChu, huoQi]), '激出了火气');
    });

    test('token nghĩa rỗng ngoài vùng chọn không vào key', () {
      expect(selectionSourceKey(paragraph, [jiChu]), '激出');
      expect(selectionSourceKey(paragraph, [huoQi, after]), '火气他');
    });

    test('bỏ qua passthrough giữa hai token được chọn', () {
      const comma = Token(
        source: '、',
        sourceStart: 2,
        kind: TokenKind.passthrough,
      );
      const withComma = [jiChu, comma, huoQi];
      expect(selectionSourceKey(withComma, [jiChu, huoQi]), '激出火气');
    });

    test('không chọn gì → key rỗng', () {
      expect(selectionSourceKey(paragraph, const []), '');
    });

    // Cụm mở đầu bằng latin toàn-hình (ＨＢＴＮシリーズ): nếu engine không ghép
    // được thì ＨＢＴＮ thành passthrough và vùng chọn chỉ cho key `シリーズ`
    // — dialog sửa VietPhrase nhận sai cụm.
    test('cụm mở đầu latin toàn-hình cho key đầy đủ', () {
      final tokens = TranslationEngine(
        dicts: [
          PhraseDictionary(DictType.vietPhrase, const {
            'ＨＢＴＮシリーズ': 'HBTN Series',
            'シリーズ': 'sê-ri',
          }),
        ],
      ).translate('ＨＢＴＮシリーズ');
      expect(tokens.single.kind, TokenKind.matched);
      expect(selectionSourceKey(tokens, [tokens.single]), 'ＨＢＴＮシリーズ');
    });

    test('giữ nguyên số toàn-hình/bán-hình trong passthrough (第３奥部, 第3奥部)', () {
      const di = Token(
        source: '第',
        sourceStart: 0,
        kind: TokenKind.matched,
        rawValue: 'thứ',
      );
      const sanFull = Token(
        source: '３',
        sourceStart: 1,
        kind: TokenKind.passthrough,
      );
      const aoBu = Token(
        source: '奥部',
        sourceStart: 2,
        kind: TokenKind.matched,
        rawValue: 'áo bộ',
      );
      final paraFull = [di, sanFull, aoBu];
      // Chọn cả 3 token
      expect(selectionSourceKey(paraFull, [di, sanFull, aoBu]), '第３奥部');
      // Chọn đầu + cuối (khi token số ở giữa không nằm trong danh sách token được chọn)
      expect(selectionSourceKey(paraFull, [di, aoBu]), '第３奥部');
      // Chọn số + đuôi
      expect(selectionSourceKey(paraFull, [sanFull, aoBu]), '３奥部');
      // Chọn đầu + số
      expect(selectionSourceKey(paraFull, [di, sanFull]), '第３');
      // Chọn riêng số
      expect(selectionSourceKey(paraFull, [sanFull]), '３');

      const sanHalf = Token(
        source: '3',
        sourceStart: 1,
        kind: TokenKind.passthrough,
      );
      final paraHalf = [di, sanHalf, aoBu];
      expect(selectionSourceKey(paraHalf, [di, aoBu]), '第3奥部');
      expect(selectionSourceKey(paraHalf, [di, sanHalf, aoBu]), '第3奥部');
      expect(selectionSourceKey(paraHalf, [sanHalf, aoBu]), '3奥部');
    });

    test('giữ nguyên chữ latin trong passthrough giữa hai token', () {
      const prefix = Token(
        source: '新',
        sourceStart: 0,
        kind: TokenKind.matched,
        rawValue: 'mới',
      );
      const latin = Token(
        source: 'Type-C',
        sourceStart: 1,
        kind: TokenKind.passthrough,
      );
      const suffix = Token(
        source: '線',
        sourceStart: 7,
        kind: TokenKind.matched,
        rawValue: 'dây',
      );
      final para = [prefix, latin, suffix];
      expect(selectionSourceKey(para, [prefix, suffix]), '新Type-C線');
      expect(selectionSourceKey(para, [prefix, latin, suffix]), '新Type-C線');
      expect(selectionSourceKey(para, [latin, suffix]), 'Type-C線');
    });
  });

  group('MultiMeaningDisplayMode in Token.displayAllWith', () {
    const multiTier = Token(
      source: '記憶',
      sourceStart: 0,
      kind: TokenKind.matched,
      rawValue: '(n)/ký ức/hồi ức/(2)/(v)/nhớ lại',
    );

    test('Phân cấp màu sắc (visualHierarchy - default)', () {
      expect(
        multiTier.displayAllWith(mode: MultiMeaningDisplayMode.visualHierarchy),
        '[(n) ký ức/hồi ức/(v) nhớ lại]',
      );
    });

    test('Đánh số phân tầng (tieredNumbered)', () {
      expect(
        multiTier.displayAllWith(mode: MultiMeaningDisplayMode.tieredNumbered),
        '[① (n) ký ức/hồi ức ‖ ② (v) nhớ lại]',
      );
    });

    test('Cổ điển (classic)', () {
      expect(
        multiTier.displayAllWith(mode: MultiMeaningDisplayMode.classic),
        '[(n) ký ức/hồi ức/(v) nhớ lại]',
      );
    });
  });
}
