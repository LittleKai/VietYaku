import '../../../core/cjk.dart';
import '../../dictionary/domain/phrase_dictionary.dart';
import 'token.dart';

/// Cụm chỉ có trong từ điển phụ (Lạc Việt > Nhật Việt > Mazii) mà VietPhrase
/// KHÔNG có — dùng để mở rộng vùng chọn khi click (hiện nghĩa trong ô Nghĩa)
/// và để đánh dấu (sát khoảng cách / in nghiêng) trong ô VietPhrase.
class SecondaryPhrase {
  /// Offset UTF-16 code unit trong văn bản nguồn.
  final int start;
  final int end;
  final String source;

  /// Nhãn từ điển tìm thấy: 'Lạc Việt' | 'Nhật Việt' | 'Mazii'.
  final String label;

  const SecondaryPhrase({
    required this.start,
    required this.end,
    required this.source,
    required this.label,
  });

  bool contains(int offset) => offset >= start && offset < end;
}

/// Quét các run token [TokenKind.unmatched] liên tiếp (kana không match
/// VietPhrase), greedy longest-match vào Lạc Việt > Nhật Việt > Mazii; chỉ
/// nhận cụm ≥ 2 rune. Vì cả run là token unmatched nên mọi cụm con chắc chắn
/// KHÔNG nằm trong UserDict/Names/VietPhrase.
List<SecondaryPhrase> findSecondaryPhrases({
  required String text,
  required List<Token> tokens,
  required PhraseDictionary lacViet,
  required PhraseDictionary jaVi,
  required PhraseDictionary mazii,
}) {
  final result = <SecondaryPhrase>[];
  var i = 0;
  while (i < tokens.length) {
    if (tokens[i].kind != TokenKind.unmatched) {
      i++;
      continue;
    }
    final runStart = tokens[i].sourceStart;
    var runEnd = runStart + tokens[i].source.length;
    var j = i;
    while (j + 1 < tokens.length &&
        tokens[j + 1].kind == TokenKind.unmatched &&
        tokens[j + 1].sourceStart == runEnd) {
      j++;
      runEnd = tokens[j].sourceStart + tokens[j].source.length;
    }
    _matchRun(text, runStart, runEnd, lacViet, jaVi, mazii, result);
    i = j + 1;
  }
  return result;
}

/// Cụm từ điển phụ bắt đầu ĐÚNG tại [offset] (greedy longest-match, giới hạn
/// trong run token unmatched chứa [offset]). Dùng khi click vào GIỮA một cụm
/// đã ghép: phải tra lại từ đúng ký tự bị click, không lấy cụm bắt đầu trước
/// đó (VD はやめて ghép はや, click や → やめ).
SecondaryPhrase? secondaryPhraseStartingAt({
  required String text,
  required List<Token> tokens,
  required int offset,
  required PhraseDictionary lacViet,
  required PhraseDictionary jaVi,
  required PhraseDictionary mazii,
}) {
  var i = 0;
  while (i < tokens.length &&
      !(offset >= tokens[i].sourceStart &&
          offset < tokens[i].sourceStart + tokens[i].source.length)) {
    i++;
  }
  if (i == tokens.length || tokens[i].kind != TokenKind.unmatched) return null;
  var runEnd = tokens[i].sourceStart + tokens[i].source.length;
  while (i + 1 < tokens.length &&
      tokens[i + 1].kind == TokenKind.unmatched &&
      tokens[i + 1].sourceStart == runEnd) {
    i++;
    runEnd = tokens[i].sourceStart + tokens[i].source.length;
  }
  return _matchAt(text, offset, runEnd, lacViet, jaVi, mazii);
}

void _matchRun(
  String text,
  int runStart,
  int runEnd,
  PhraseDictionary lacViet,
  PhraseDictionary jaVi,
  PhraseDictionary mazii,
  List<SecondaryPhrase> out,
) {
  var pos = runStart;
  while (pos < runEnd) {
    final phrase = _matchAt(text, pos, runEnd, lacViet, jaVi, mazii);
    if (phrase == null) {
      pos += runeLengthAt(text, pos);
      continue;
    }
    out.add(phrase);
    pos = phrase.end;
  }
}

/// Cụm dài nhất bắt đầu tại [pos], không vượt quá [runEnd]; null nếu không có.
SecondaryPhrase? _matchAt(
  String text,
  int pos,
  int runEnd,
  PhraseDictionary lacViet,
  PhraseDictionary jaVi,
  PhraseDictionary mazii,
) {
  final firstUnit = text.codeUnitAt(pos);
  var maxLen = lacViet.maxLenFor(firstUnit);
  final jl = jaVi.maxLenFor(firstUnit);
  if (jl > maxLen) maxLen = jl;
  final ml = mazii.maxLenFor(firstUnit);
  if (ml > maxLen) maxLen = ml;
  if (maxLen > runEnd - pos) maxLen = runEnd - pos;

  for (var len = maxLen; len >= 2; len--) {
    final endPos = pos + len;
    // Không cắt đôi surrogate pair (lead surrogate ở cuối candidate).
    final lastUnit = text.codeUnitAt(endPos - 1);
    if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) continue;
    final candidate = text.substring(pos, endPos);
    if (_runeCount(candidate) < 2) continue;
    final label = _priorityLabel(candidate, lacViet, jaVi, mazii);
    if (label != null) {
      return SecondaryPhrase(
        start: pos,
        end: endPos,
        source: candidate,
        label: label,
      );
    }
  }
  return null;
}

String? _priorityLabel(
  String key,
  PhraseDictionary lacViet,
  PhraseDictionary jaVi,
  PhraseDictionary mazii,
) {
  if (lacViet.entries.containsKey(key)) return 'Lạc Việt';
  if (jaVi.entries.containsKey(key)) return 'Nhật Việt';
  if (mazii.entries.containsKey(key)) return 'Mazii';
  return null;
}

int _runeCount(String s) {
  var count = 0;
  var i = 0;
  while (i < s.length) {
    i += runeLengthAt(s, i);
    count++;
  }
  return count;
}
