import '../../../core/cjk.dart';

/// Lọc sự kiện clipboard trước khi dịch: chỉ nhận CJK, debounce, chống lặp và
/// bỏ qua nội dung vừa do chính VietYaku ghi.
class ClipboardReadFilter {
  final Duration debounce;
  final Duration ownWriteWindow;
  int? _lastAcceptedHash;
  DateTime? _lastAcceptedAt;
  int? _ownWriteHash;
  DateTime? _ownWriteAt;

  ClipboardReadFilter({
    this.debounce = const Duration(milliseconds: 300),
    this.ownWriteWindow = const Duration(seconds: 2),
  });

  void markOwnWrite(String text, DateTime now) {
    _ownWriteHash = _fnv1a(text);
    _ownWriteAt = now;
  }

  bool shouldAccept(String text, DateTime now) {
    if (text.isEmpty || !_containsCjk(text)) return false;
    final hash = _fnv1a(text);
    if (_ownWriteHash == hash &&
        _ownWriteAt != null &&
        now.difference(_ownWriteAt!) <= ownWriteWindow) {
      return false;
    }
    if (_lastAcceptedHash == hash) return false;
    if (_lastAcceptedAt != null &&
        now.difference(_lastAcceptedAt!) < debounce) {
      return false;
    }
    _lastAcceptedHash = hash;
    _lastAcceptedAt = now;
    return true;
  }
}

bool _containsCjk(String text) {
  for (var i = 0; i < text.length; i++) {
    if (isCjkCodePoint(codePointAt(text, i))) return true;
    i += runeLengthAt(text, i) - 1;
  }
  return false;
}

int _fnv1a(String text) {
  var hash = 0x811C9DC5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
