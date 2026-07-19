import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/cjk.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
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
        const Token(
          source: '。」',
          sourceStart: 3,
          kind: TokenKind.passthrough,
        ),
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
  });
}
