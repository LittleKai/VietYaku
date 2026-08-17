import '../../dictionary/domain/dict_type.dart';
import 'vietphrase_value.dart';

enum TokenKind {
  /// Match được trong từ điển cụm (UserDict/Names/VietPhrase).
  matched,

  /// Chữ Hán đơn fallback âm Hán Việt (ChinesePhienAmWords).
  hanViet,

  /// Đoạn không phải CJK, giữ nguyên.
  passthrough,

  /// CJK nhưng không match (kana, ký tự lạ), giữ nguyên.
  unmatched,
}

/// Nghĩa đầu tiên của value `nghĩa1/nghĩa2/...`.
String firstMeaning(String value) {
  return firstVietPhraseMeaning(value);
}

class Token {
  final String source;

  /// Offset UTF-16 code unit trong văn bản gốc.
  final int sourceStart;
  final TokenKind kind;
  final DictType? dictType;

  /// Value nguyên bản từ dict (`nghĩa1/nghĩa2/...`).
  /// Null với passthrough/unmatched.
  final String? rawValue;

  const Token({
    required this.source,
    required this.sourceStart,
    required this.kind,
    this.dictType,
    this.rawValue,
  });

  /// Nghĩa đầu tiên của value. Null với passthrough/unmatched.
  String? get meaning => rawValue == null ? null : firstMeaning(rawValue!);

  /// Văn bản hiển thị ở kết quả dịch (một nghĩa).
  String get display => meaning ?? source;

  /// Tab VietPhrase một nghĩa: thêm nhãn từ loại gọn nếu nghĩa có phân loại.
  String get displayWithPartOfSpeech {
    final raw = rawValue;
    if (raw == null) return source;
    final meanings = parseVietPhraseValue(raw);
    return meanings.isEmpty ? '' : meanings.first.displayPrimaryText;
  }

  /// Hiển thị đa nghĩa theo mode cấu hình:
  /// [bracketSingle] bọc ngoặc vuông cả cụm chỉ có 1 nghĩa.
  /// [mode] quy định kiểu hiển thị (phân cấp màu sắc, đánh số phân tầng, gọn gàng chỉ số, cổ điển).
  String displayAllWith({
    bool bracketSingle = false,
    MultiMeaningDisplayMode mode = MultiMeaningDisplayMode.visualHierarchy,
  }) {
    final raw = rawValue;
    if (raw == null) return source;
    final meanings = parseVietPhraseValue(raw);
    if (meanings.isEmpty) return source;
    final alternativeCount = meanings.fold<int>(
      0,
      (count, meaning) => count + meaning.alternatives.length,
    );
    if (alternativeCount == 1 && !bracketSingle) return meanings.first.displayText;

    switch (mode) {
      case MultiMeaningDisplayMode.tieredNumbered:
        if (meanings.length >= 2) {
          final parts = <String>[];
          for (var i = 0; i < meanings.length; i++) {
            final numCircle = circledNumber(i + 1);
            parts.add('$numCircle ${meanings[i].displayText}');
          }
          return '[${parts.join(' ‖ ')}]';
        }
        return '[${meanings.first.displayText}]';

      case MultiMeaningDisplayMode.visualHierarchy:
      case MultiMeaningDisplayMode.classic:
        final parts = meanings.map((meaning) => meaning.displayText).toList();
        return '[${parts.join('/')}]';
    }
  }

  String get displayAll => displayAllWith();

  @override
  String toString() => 'Token($kind, "$source" → "$display")';
}
