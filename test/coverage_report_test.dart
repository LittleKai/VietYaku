import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/analysis/domain/coverage_report.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

/// Dựng chuỗi token liền mạch từ `(text, kind)` — sourceStart cộng dồn đúng
/// như engine trả về.
List<Token> _tokens(
  List<(String, TokenKind)> parts,
  Map<String, String> values,
) {
  final tokens = <Token>[];
  var start = 0;
  for (final (text, kind) in parts) {
    tokens.add(
      Token(
        source: text,
        sourceStart: start,
        kind: kind,
        rawValue: kind == TokenKind.matched
            ? (values[text] ?? 'nghĩa-$text')
            : null,
      ),
    );
    start += text.length;
  }
  return tokens;
}

PhraseDictionary _dict(DictType type, [Map<String, String> entries = const {}]) =>
    PhraseDictionary(type, {...entries});

CoverageReport _report(
  List<(String, TokenKind)> parts, {
  TranslationMode mode = TranslationMode.japanese,
  Map<String, String> names = const {},
  Map<String, String> vietPhrase = const {},
  Map<String, String> values = const {},
}) => buildCoverageReport(
  tokens: _tokens(parts, values),
  mode: mode,
  names: _dict(DictType.names, names),
  vietPhrase: _dict(DictType.vietPhrase, vietPhrase),
);

void main() {
  group('độ phủ', () {
    test('chỉ token matched mới tính là đã phủ', () {
      final report = _report([
        ('少女', TokenKind.matched),
        ('は', TokenKind.unmatched),
        ('走', TokenKind.hanViet),
        ('った', TokenKind.unmatched),
      ]);
      expect(report.totalCjk, 6);
      expect(report.matchedCjk, 2);
      expect(report.uncoveredCjk, 4);
      expect(report.coverage, closeTo(2 / 6, 1e-9));
    });

    test('ký tự không phải CJK không vào mẫu số', () {
      final report = _report([
        ('Hello, ', TokenKind.passthrough),
        ('世界', TokenKind.matched),
      ]);
      expect(report.totalCjk, 2);
      expect(report.coverage, 1);
    });

    test('văn bản không có CJK coi như phủ đủ', () {
      final report = _report([('abc', TokenKind.passthrough)]);
      expect(report.totalCjk, 0);
      expect(report.coverage, 1);
      expect(report.chunks, isEmpty);
    });
  });

  group('bảng cụm chưa dịch', () {
    test('gộp token liền nhau rồi cắt theo loại chữ', () {
      final report = _report([
        ('ハルカ', TokenKind.unmatched),
        ('さん', TokenKind.unmatched),
        ('。', TokenKind.passthrough),
      ]);
      expect(report.chunks.map((c) => c.source), ['ハルカ', 'さん']);
      expect(report.chunks.first.script, ChunkScript.katakana);
      expect(report.chunks.first.length, 3);
      expect(report.chunks.last.script, ChunkScript.hiragana);
    });

    test('đếm tần suất và giữ vị trí xuất hiện đầu tiên', () {
      final report = _report([
        ('あの', TokenKind.unmatched),
        ('人', TokenKind.matched),
        ('、', TokenKind.passthrough),
        ('あの', TokenKind.unmatched),
        ('人', TokenKind.matched),
      ]);
      final chunk = report.chunks.single;
      expect(chunk.source, 'あの');
      expect(chunk.count, 2);
      expect(chunk.firstStart, 0);
      expect(chunk.impact, 4);
      expect(report.totalOccurrences, 2);
    });

    test('xếp theo tần suất giảm dần, hòa thì cụm dài lên trước', () {
      final report = _report([
        ('ハルカ', TokenKind.unmatched),
        ('a', TokenKind.passthrough),
        ('ミク', TokenKind.unmatched),
        ('a', TokenKind.passthrough),
        ('ミク', TokenKind.unmatched),
        ('a', TokenKind.passthrough),
        ('リン', TokenKind.unmatched),
      ]);
      expect(report.chunks.map((c) => c.source), ['ミク', 'ハルカ', 'リン']);
    });

    test('bỏ hiragana đơn (trợ từ は/を/が) khỏi bảng', () {
      final report = _report([
        ('走', TokenKind.hanViet),
        ('る', TokenKind.unmatched),
        ('人', TokenKind.matched),
        ('は', TokenKind.unmatched),
      ]);
      expect(report.chunks.map((c) => c.source), ['走']);
    });

    test('chữ Hán rơi về phiên âm vẫn bị coi là chưa dịch', () {
      final report = _report([
        ('凄', TokenKind.hanViet),
        ('絶', TokenKind.hanViet),
      ]);
      expect(report.chunks.single.source, '凄絶');
      expect(report.chunks.single.script, ChunkScript.kanji);
    });

    test('offset đầu tiên trỏ đúng vào văn bản nguồn', () {
      const text = '私はハルカです';
      final report = _report([
        ('私', TokenKind.matched),
        ('は', TokenKind.unmatched),
        ('ハルカ', TokenKind.unmatched),
        ('です', TokenKind.unmatched),
      ]);
      final chunk = report.chunks.firstWhere((c) => c.source == 'ハルカ');
      expect(
        text.substring(chunk.firstStart, chunk.firstStart + 'ハルカ'.length),
        'ハルカ',
      );
    });
  });

  group('ứng viên tên riêng', () {
    List<(String, TokenKind)> repeated(String word, int times) => [
      for (var i = 0; i < times; i++) ...[
        (word, TokenKind.unmatched),
        ('。', TokenKind.passthrough),
      ],
    ];

    test('katakana ≥2 ký tự lặp đủ số lần → ứng viên (mode Nhật)', () {
      final report = _report(repeated('ハルカ', minNameOccurrences));
      expect(report.nameCandidates.map((c) => c.source), ['ハルカ']);
    });

    test('lặp thiếu một lần thì không phải ứng viên', () {
      final report = _report(repeated('ハルカ', minNameOccurrences - 1));
      expect(report.nameCandidates, isEmpty);
      expect(report.chunks, isNotEmpty);
    });

    test('katakana 1 ký tự không phải ứng viên', () {
      final report = _report(repeated('ン', minNameOccurrences + 2));
      expect(report.nameCandidates, isEmpty);
    });

    test('đã có trong Names hoặc VietPhrase thì bỏ qua', () {
      final tokens = repeated('ハルカ', minNameOccurrences);
      expect(_report(tokens, names: {'ハルカ': 'Haruka'}).nameCandidates, isEmpty);
      expect(
        _report(tokens, vietPhrase: {'ハルカ': 'xa xăm'}).nameCandidates,
        isEmpty,
      );
    });

    test('mode Nhật không nhận cụm Hán làm tên riêng', () {
      final report = _report(repeated('凄絶', minNameOccurrences));
      expect(report.nameCandidates, isEmpty);
    });

    test('mode Trung nhận cụm Hán 2–3 ký tự', () {
      final report = _report(
        repeated('林动', minNameOccurrences),
        mode: TranslationMode.chinese,
      );
      expect(report.nameCandidates.map((c) => c.source), ['林动']);
    });

    test('mode Trung bỏ cụm Hán dài hơn 3 ký tự', () {
      final report = _report(
        repeated('大千世界录', minNameOccurrences),
        mode: TranslationMode.chinese,
      );
      expect(report.nameCandidates, isEmpty);
    });
  });

  group('không nhất quán', () {
    test('chỗ dịch nguyên cụm, chỗ bị cắt nhỏ → báo lệch', () {
      final report = _report([
        ('少女', TokenKind.matched),
        ('、', TokenKind.passthrough),
        ('少', TokenKind.matched),
        ('女', TokenKind.matched),
      ]);
      final term = report.inconsistentTerms.single;
      expect(term.source, '少女');
      expect(term.count, 1);
      expect(term.firstStart, 0);
      expect(term.variantCount, 1);
      expect(term.variants.single.segmentation, '少 | 女');
      expect(term.variants.single.meaning, 'nghĩa-少 nghĩa-女');
      expect(term.variants.single.firstStart, 3);
    });

    test('nằm gọn trong cụm dài hơn là ghép đúng, không báo', () {
      final report = _report([
        ('少女', TokenKind.matched),
        ('、', TokenKind.passthrough),
        ('美少女', TokenKind.matched),
      ]);
      expect(report.inconsistentTerms, isEmpty);
    });

    test('cắt giống nhau ở mọi chỗ thì không báo', () {
      final report = _report([
        ('少女', TokenKind.matched),
        ('、', TokenKind.passthrough),
        ('少女', TokenKind.matched),
      ]);
      expect(report.inconsistentTerms, isEmpty);
    });

    test('gộp các chỗ lệch giống nhau thành một biến thể', () {
      final report = _report([
        ('少女', TokenKind.matched),
        ('少', TokenKind.matched),
        ('女', TokenKind.matched),
        ('少', TokenKind.matched),
        ('女', TokenKind.matched),
      ]);
      final term = report.inconsistentTerms.single;
      expect(term.variants.length, 1);
      expect(term.variants.single.count, 2);
    });
  });

  group('cảnh báo', () {
    test('ngoặc mở không có ngoặc đóng', () {
      final report = _report([
        ('「', TokenKind.passthrough),
        ('少女', TokenKind.matched),
      ]);
      final warning = report.warnings.single;
      expect(warning.kind, TextWarningKind.unclosedBracket);
      expect(warning.excerpt, '「');
      expect(warning.offset, 0);
    });

    test('ngoặc đóng thừa', () {
      final report = _report([
        ('少女', TokenKind.matched),
        ('」', TokenKind.passthrough),
      ]);
      final warning = report.warnings.single;
      expect(warning.kind, TextWarningKind.strayCloseBracket);
      expect(warning.offset, 2);
    });

    test('ngoặc cân bằng thì im lặng', () {
      final report = _report([
        ('「', TokenKind.passthrough),
        ('少女', TokenKind.matched),
        ('」', TokenKind.passthrough),
      ]);
      expect(report.warnings, isEmpty);
    });

    test('số toàn rộng bị nuốt mất trong bản dịch', () {
      final report = _report(
        [('第３章', TokenKind.matched)],
        values: {'第３章': 'chương mới'},
      );
      final warning = report.warnings.single;
      expect(warning.kind, TextWarningKind.missingNumber);
      expect(warning.excerpt, '3');
      expect(warning.offset, 1);
    });

    test('số giữ nguyên trong bản dịch thì không báo', () {
      final report = _report(
        [('第３章', TokenKind.matched)],
        values: {'第３章': 'chương 3'},
      );
      expect(report.warnings, isEmpty);
    });

    test('số viết bằng chữ Hán không tính là mất số', () {
      final report = _report(
        [('第三章', TokenKind.matched)],
        values: {'第三章': 'chương ba'},
      );
      expect(report.warnings, isEmpty);
    });
  });
}
