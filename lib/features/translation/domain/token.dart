import '../../dictionary/domain/dict_type.dart';

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
  final slash = value.indexOf('/');
  final first = slash < 0 ? value : value.substring(0, slash);
  return first.trim();
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

  /// Hiển thị đa nghĩa kiểu QuickTranslator: >1 nghĩa → `[nghĩa1/nghĩa2]`.
  /// [bracketSingle] bọc ngoặc vuông cả cụm chỉ có 1 nghĩa.
  String displayAllWith({bool bracketSingle = false}) {
    final raw = rawValue;
    if (raw == null) return source;
    final parts = raw
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return source;
    if (parts.length == 1 && !bracketSingle) return parts.first;
    return '[${parts.join('/')}]';
  }

  String get displayAll => displayAllWith();

  @override
  String toString() => 'Token($kind, "$source" → "$display")';
}
