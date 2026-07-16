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

class Token {
  final String source;

  /// Offset UTF-16 code unit trong văn bản gốc.
  final int sourceStart;
  final TokenKind kind;
  final DictType? dictType;

  /// Nghĩa hiển thị (nghĩa đầu tiên của value). Null với passthrough/unmatched.
  final String? meaning;

  const Token({
    required this.source,
    required this.sourceStart,
    required this.kind,
    this.dictType,
    this.meaning,
  });

  /// Văn bản hiển thị ở kết quả dịch.
  String get display => meaning ?? source;

  @override
  String toString() => 'Token($kind, "$source" → "${meaning ?? source}")';
}
