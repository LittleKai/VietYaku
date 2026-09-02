import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/secondary_phrase.dart';
import 'package:vietyaku/features/translation/domain/token.dart';

PhraseDictionary _dict(DictType type, Map<String, String> entries) =>
    PhraseDictionary(type, entries);

/// Mỗi rune kana → 1 token unmatched (như engine sinh ra khi không match).
List<Token> _unmatchedRunes(String text, {int start = 0}) {
  final tokens = <Token>[];
  var i = start;
  for (final rune in text.runes) {
    final s = String.fromCharCode(rune);
    tokens.add(Token(source: s, sourceStart: i, kind: TokenKind.unmatched));
    i += s.length;
  }
  return tokens;
}

void main() {
  final empty = _dict(DictType.mazii, const {});

  test('nhận cụm kana chỉ có trong Lạc Việt (≥2 rune)', () {
    const text = 'たりしていた';
    final lacViet = _dict(DictType.lacViet, {
      'たりしていた': 'nào là...; chẳng hạn như',
    });
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: lacViet,
      jaVi: empty,
      mazii: empty,
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.source, 'たりしていた');
    expect(phrases.first.start, 0);
    expect(phrases.first.end, text.length);
    expect(phrases.first.label, 'Lạc Việt');
  });

  test('greedy longest-match: cụm dài thắng cụm ngắn', () {
    const text = 'たりしていた';
    final lacViet = _dict(DictType.lacViet, {'たり': 'ngắn', 'たりしていた': 'dài'});
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: lacViet,
      jaVi: empty,
      mazii: empty,
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.source, 'たりしていた');
  });

  test('ưu tiên Lạc Việt > Nhật Việt > Mazii khi cùng độ dài', () {
    const text = 'なので';
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: _dict(DictType.lacViet, {'なので': 'lv'}),
      jaVi: _dict(DictType.jaVi, {'なので': 'nv'}),
      mazii: _dict(DictType.mazii, {'なので': 'mz'}),
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.label, 'Lạc Việt');
  });

  test('bỏ qua cụm chỉ 1 rune', () {
    const text = 'は';
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: _dict(DictType.lacViet, {'は': 'là'}),
      jaVi: empty,
      mazii: empty,
    );
    expect(phrases, isEmpty);
  });

  test('không quét qua token matched (không thuộc run unmatched)', () {
    // 私 matched, りして unmatched. Cụm りして có trong Nhật Việt.
    const text = '私りして';
    final tokens = <Token>[
      Token(
        source: '私',
        sourceStart: 0,
        kind: TokenKind.matched,
        dictType: DictType.vietPhrase,
        rawValue: 'tôi',
      ),
      ..._unmatchedRunes('りして', start: 1),
    ];
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: tokens,
      lacViet: empty,
      jaVi: _dict(DictType.jaVi, {'りして': 'nv'}),
      mazii: empty,
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.source, 'りして');
    expect(phrases.first.start, 1);
    expect(phrases.first.label, 'Nhật Việt');
  });

  group('secondaryPhraseStartingAt (click giữa cụm)', () {
    // はやめて: はや có trong Nhật Việt (cụm greedy chiếm 0..2),
    // やめ có trong Lạc Việt nhưng bị cụm はや che mất.
    const text = 'はやめて';
    final lacViet = _dict(DictType.lacViet, {'やめ': 'thôi, ngừng'});
    final jaVi = _dict(DictType.jaVi, {'はや': 'nhanh'});

    test('click や (giữa cụm はや) → cụm やめ bắt đầu tại vị trí click', () {
      final phrase = secondaryPhraseStartingAt(
        text: text,
        tokens: _unmatchedRunes(text),
        offset: 1,
        lacViet: lacViet,
        jaVi: jaVi,
        mazii: empty,
      );
      expect(phrase, isNotNull);
      expect(phrase!.source, 'やめ');
      expect(phrase.start, 1);
      expect(phrase.end, 3);
      expect(phrase.label, 'Lạc Việt');
    });

    test('không có cụm nào bắt đầu tại vị trí click → null', () {
      final phrase = secondaryPhraseStartingAt(
        text: text,
        tokens: _unmatchedRunes(text),
        offset: 1,
        lacViet: empty,
        jaVi: jaVi,
        mazii: empty,
      );
      expect(phrase, isNull);
    });

    test('vị trí thuộc token matched → null', () {
      const src = '私やめ';
      final tokens = <Token>[
        Token(
          source: '私',
          sourceStart: 0,
          kind: TokenKind.matched,
          dictType: DictType.vietPhrase,
          rawValue: 'tôi',
        ),
        ..._unmatchedRunes('やめ', start: 1),
      ];
      final phrase = secondaryPhraseStartingAt(
        text: src,
        tokens: tokens,
        offset: 0,
        lacViet: lacViet,
        jaVi: empty,
        mazii: empty,
      );
      expect(phrase, isNull);
    });

    test('không vượt ra ngoài run unmatched', () {
      // 私 matched ở giữa: cụm やめ (1..3) không được nối sang sau 私.
      const src = 'はや私め';
      final tokens = <Token>[
        ..._unmatchedRunes('はや'),
        Token(
          source: '私',
          sourceStart: 2,
          kind: TokenKind.matched,
          dictType: DictType.vietPhrase,
          rawValue: 'tôi',
        ),
        ..._unmatchedRunes('め', start: 3),
      ];
      final phrase = secondaryPhraseStartingAt(
        text: src,
        tokens: tokens,
        offset: 1,
        lacViet: lacViet,
        jaVi: jaVi,
        mazii: empty,
      );
      expect(phrase, isNull);
    });
  });

  test('không có cụm phụ → rỗng', () {
    const text = 'あいうえお';
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: empty,
      jaVi: empty,
      mazii: empty,
    );
    expect(phrases, isEmpty);
  });

  test('nhận cụm đã lưu trong OnlineDict để chọn lại trúng nguyên cụm', () {
    const text = 'たりしていた';
    final onlineDict = _dict(DictType.onlineDict, {
      'たりしていた': '<<Mazii Online>>\nnào là...; chẳng hạn như',
    });
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: empty,
      jaVi: empty,
      mazii: empty,
      onlineDict: onlineDict,
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.source, 'たりしていた');
    expect(phrases.first.label, 'Online');
  });

  test('nhận cụm đã lưu trong AiDict', () {
    const text = 'たりしていた';
    final aiDict = _dict(DictType.aiDict, {
      'たりしていた': '<<AI Dịch>>\n1. Nghĩa tiếng Việt: nào là...',
    });
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: empty,
      jaVi: empty,
      mazii: empty,
      aiDict: aiDict,
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.label, 'AI Dịch');
  });

  test('từ điển gốc thắng OnlineDict/AiDict khi cùng khớp một cụm', () {
    const text = 'たりしていた';
    final phrases = findSecondaryPhrases(
      text: text,
      tokens: _unmatchedRunes(text),
      lacViet: _dict(DictType.lacViet, {'たりしていた': 'nào là...'}),
      jaVi: empty,
      mazii: empty,
      onlineDict: _dict(DictType.onlineDict, {'たりしていた': 'x'}),
      aiDict: _dict(DictType.aiDict, {'たりしていた': 'y'}),
    );
    expect(phrases, hasLength(1));
    expect(phrases.first.label, 'Lạc Việt');
  });

  test('secondaryPhraseStartingAt cũng thấy cụm AiDict', () {
    const text = 'たりしていた';
    final phrase = secondaryPhraseStartingAt(
      text: text,
      tokens: _unmatchedRunes(text),
      offset: 0,
      lacViet: empty,
      jaVi: empty,
      mazii: empty,
      aiDict: _dict(DictType.aiDict, {'たりしていた': 'y'}),
    );
    expect(phrase, isNotNull);
    expect(phrase!.label, 'AI Dịch');
  });
}
