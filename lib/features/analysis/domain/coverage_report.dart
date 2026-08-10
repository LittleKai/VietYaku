import '../../../core/cjk.dart';
import '../../dictionary/domain/phrase_dictionary.dart';
import '../../translation/domain/token.dart';
import '../../translation/domain/translation_engine.dart';

/// Loại chữ của một cụm chưa dịch. Dùng để lọc ứng viên tên riêng (katakana ở
/// mode Nhật, Hán ở mode Trung) và để bỏ trợ từ hiragana đơn khỏi bảng tần suất.
enum ChunkScript { katakana, hiragana, kanji }

/// Một cụm chưa dịch (chuỗi ký tự cùng loại chữ nằm trong vùng token không
/// match) kèm số lần xuất hiện trong văn bản.
class UnmatchedChunk {
  /// Văn bản cụm — lấy từ `Token.source`, tức là bản đã quy phồn→giản ở mode
  /// Trung, đúng dạng key của từ điển.
  final String source;
  final ChunkScript script;
  final int count;

  /// Offset UTF-16 của lần xuất hiện đầu tiên, tính trên văn bản nguồn gốc.
  final int firstStart;

  /// Số rune của cụm.
  final int length;

  const UnmatchedChunk({
    required this.source,
    required this.script,
    required this.count,
    required this.firstStart,
    required this.length,
  });

  /// Số ký tự CJK cụm này chiếm trong toàn văn — thước đo "thêm mục này thì
  /// độ phủ tăng bao nhiêu".
  int get impact => count * length;
}

/// Một cách cắt cụm khác với cách cắt "nguyên cụm" của [InconsistentTerm].
class TermVariant {
  /// Các token phủ chỗ này, nối bằng ` | ` (VD `大少 | 女`).
  final String segmentation;

  /// Nghĩa tương ứng của chuỗi token đó.
  final String meaning;
  final int count;
  final int firstStart;

  const TermVariant({
    required this.segmentation,
    required this.meaning,
    required this.count,
    required this.firstStart,
  });
}

/// Cùng một chuỗi nguồn nhưng chỗ thì dịch nguyên cụm, chỗ khác lại bị cắt
/// thành nhiều token → ra nghĩa khác nhau trong cùng văn bản.
class InconsistentTerm {
  final String source;

  /// Nghĩa khi được dịch nguyên cụm.
  final String meaning;

  /// Số lần được dịch nguyên cụm.
  final int count;
  final int firstStart;
  final List<TermVariant> variants;

  const InconsistentTerm({
    required this.source,
    required this.meaning,
    required this.count,
    required this.firstStart,
    required this.variants,
  });

  int get variantCount =>
      variants.fold(0, (sum, variant) => sum + variant.count);
}

enum TextWarningKind {
  /// Ngoặc mở không có ngoặc đóng.
  unclosedBracket,

  /// Ngoặc đóng không khớp ngoặc mở nào đang treo.
  strayCloseBracket,

  /// Dãy số có trong nguồn nhưng không thấy trong bản dịch.
  missingNumber,
}

/// Cảnh báo rẻ tiền: quét trên chính văn bản nguồn / bản dịch, không cần
/// từ điển hay ngữ pháp.
class TextWarning {
  final TextWarningKind kind;

  /// Ký tự ngoặc hoặc dãy số liên quan.
  final String excerpt;

  /// Offset UTF-16 trên văn bản nguồn.
  final int offset;

  const TextWarning({
    required this.kind,
    required this.excerpt,
    required this.offset,
  });
}

/// Kết quả quét một lượt dịch: độ phủ + bảng cụm chưa dịch + ứng viên tên riêng.
class CoverageReport {
  /// Tổng ký tự CJK trong văn bản.
  final int totalCjk;

  /// Ký tự CJK nằm trong token match được từ điển cụm.
  final int matchedCjk;

  /// Cụm chưa dịch, đã xếp theo tần suất giảm dần.
  final List<UnmatchedChunk> chunks;

  /// Tập con của [chunks] gần như chắc chắn là tên riêng (xem [buildCoverageReport]).
  final List<UnmatchedChunk> nameCandidates;

  /// Cụm bị cắt không nhất quán, xếp theo số chỗ lệch giảm dần.
  final List<InconsistentTerm> inconsistentTerms;

  /// Cảnh báo ngoặc lệch / số bị mất, xếp theo vị trí trong văn bản.
  final List<TextWarning> warnings;

  const CoverageReport({
    required this.totalCjk,
    required this.matchedCjk,
    required this.chunks,
    required this.nameCandidates,
    required this.inconsistentTerms,
    required this.warnings,
  });

  /// Tỷ lệ 0–1; văn bản không có ký tự CJK nào coi như phủ đủ.
  double get coverage => totalCjk == 0 ? 1 : matchedCjk / totalCjk;

  int get uncoveredCjk => totalCjk - matchedCjk;

  /// Tổng số lượt xuất hiện của mọi cụm chưa dịch.
  int get totalOccurrences =>
      chunks.fold(0, (sum, chunk) => sum + chunk.count);
}

/// Số lần lặp tối thiểu để một cụm được coi là tên riêng.
const minNameOccurrences = 3;

/// Quét [tokens] của một lượt dịch:
///
/// - Độ phủ = ký tự CJK trong token [TokenKind.matched] / tổng ký tự CJK.
///   Chữ Hán đơn rơi về phiên âm Hán Việt ([TokenKind.hanViet]) KHÔNG tính là
///   đã phủ — đó chính là chỗ còn thiếu mục từ điển.
/// - Bảng cụm chưa dịch: gom các token liền nhau chưa match thành run, cắt run
///   theo loại chữ (katakana / hiragana / Hán) rồi đếm theo văn bản cụm.
///   Bỏ cụm hiragana 1 ký tự — trợ từ は/を/が không có trong VietPhrase và chỉ
///   làm nhiễu bảng.
/// - Ứng viên tên riêng: cụm lặp ≥ [minNameOccurrences] lần, katakana ≥2 ký tự
///   (mode Nhật) hoặc Hán 2–3 ký tự (mode Trung), và không có trong [names] lẫn
///   [vietPhrase].
/// - Không nhất quán: chuỗi được dịch nguyên cụm ở chỗ này nhưng chỗ khác lại
///   bị cắt thành ≥2 token (xem [_findInconsistentTerms]).
/// - Cảnh báo: ngoặc lệch + số có trong nguồn mà mất trong bản dịch.
CoverageReport buildCoverageReport({
  required List<Token> tokens,
  required TranslationMode mode,
  required PhraseDictionary names,
  required PhraseDictionary vietPhrase,
}) {
  var totalCjk = 0;
  var matchedCjk = 0;
  for (final token in tokens) {
    final cjk = _cjkRuneCount(token.source);
    totalCjk += cjk;
    if (token.kind == TokenKind.matched) matchedCjk += cjk;
  }

  final accum = <String, _ChunkAccum>{};
  var i = 0;
  while (i < tokens.length) {
    if (!_isUncovered(tokens[i].kind)) {
      i++;
      continue;
    }
    final runStart = tokens[i].sourceStart;
    final buffer = StringBuffer(tokens[i].source);
    var runEnd = runStart + tokens[i].source.length;
    var j = i;
    while (j + 1 < tokens.length &&
        _isUncovered(tokens[j + 1].kind) &&
        tokens[j + 1].sourceStart == runEnd) {
      j++;
      buffer.write(tokens[j].source);
      runEnd = tokens[j].sourceStart + tokens[j].source.length;
    }
    _collectChunks(buffer.toString(), runStart, accum);
    i = j + 1;
  }

  final chunks =
      accum.values
          .map(
            (a) => UnmatchedChunk(
              source: a.source,
              script: a.script,
              count: a.count,
              firstStart: a.firstStart,
              length: a.length,
            ),
          )
          .toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) return byCount;
          final byLength = b.length.compareTo(a.length);
          if (byLength != 0) return byLength;
          return a.firstStart.compareTo(b.firstStart);
        });

  final nameCandidates = chunks
      .where(
        (c) =>
            _matchesNameShape(c, mode) &&
            !names.entries.containsKey(c.source) &&
            !vietPhrase.entries.containsKey(c.source),
      )
      .toList(growable: false);

  // Token phủ liền mạch toàn văn bản nên nối `source` lại là dựng đúng văn bản
  // engine đã tra (mode Trung: bản đã quy giản thể), offset khớp `sourceStart`.
  final source = tokens.map((t) => t.source).join();
  final output = tokens.map((t) => t.displayAll).join();

  return CoverageReport(
    totalCjk: totalCjk,
    matchedCjk: matchedCjk,
    chunks: chunks,
    nameCandidates: nameCandidates,
    inconsistentTerms: _findInconsistentTerms(tokens, source),
    warnings: _findWarnings(source, output),
  );
}

/// Chuỗi được dịch nguyên cụm ở chỗ này nhưng chỗ khác lại bị cắt thành ≥2
/// token → cùng một chuỗi ra hai nghĩa khác nhau trong một chương.
///
/// CHỈ tính trường hợp bị cắt nhỏ. Chuỗi nằm gọn trong MỘT token dài hơn
/// (`少女` trong `美少女`) là cách ghép đúng của greedy longest-match, không
/// phải lỗi — báo ra chỉ làm ngập bảng vì tiếng Nhật/Trung lồng cụm rất nhiều.
List<InconsistentTerm> _findInconsistentTerms(List<Token> tokens, String text) {
  final terms = <String, _TermAccum>{};
  for (final token in tokens) {
    if (token.kind != TokenKind.matched) continue;
    if (_runeCount(token.source) < 2) continue;
    final existing = terms[token.source];
    if (existing == null) {
      terms[token.source] = _TermAccum(
        meaning: token.displayAll,
        firstStart: token.sourceStart,
      );
    } else {
      existing.count++;
    }
  }
  if (terms.isEmpty) return const [];

  // Gom theo code unit đầu để mỗi vị trí chỉ thử vài ứng viên thay vì quét cả
  // văn bản một lần cho từng cụm.
  final byFirstUnit = <int, List<String>>{};
  for (final term in terms.keys) {
    byFirstUnit.putIfAbsent(term.codeUnitAt(0), () => <String>[]).add(term);
  }

  for (var pos = 0; pos < text.length; pos++) {
    final candidates = byFirstUnit[text.codeUnitAt(pos)];
    if (candidates == null) continue;
    for (final term in candidates) {
      if (!text.startsWith(term, pos)) continue;
      final first = _tokenIndexAt(tokens, pos);
      var last = first;
      while (last + 1 < tokens.length &&
          tokens[last + 1].sourceStart < pos + term.length) {
        last++;
      }
      if (last == first) continue; // nằm gọn trong 1 token → không phải lỗi
      final covering = tokens.getRange(first, last + 1);
      terms[term]!.addVariant(
        covering.map((t) => t.source).join(' | '),
        covering.map((t) => t.displayAll).join(' '),
        pos,
      );
    }
  }

  return terms.entries
      .where((e) => e.value.variants.isNotEmpty)
      .map(
        (e) => InconsistentTerm(
          source: e.key,
          meaning: e.value.meaning,
          count: e.value.count,
          firstStart: e.value.firstStart,
          variants: e.value.variants.entries
              .map(
                (v) => TermVariant(
                  segmentation: v.key,
                  meaning: v.value.meaning,
                  count: v.value.count,
                  firstStart: v.value.firstStart,
                ),
              )
              .toList(growable: false),
        ),
      )
      .toList()
    ..sort((a, b) {
      final byVariants = b.variantCount.compareTo(a.variantCount);
      if (byVariants != 0) return byVariants;
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return a.firstStart.compareTo(b.firstStart);
    });
}

/// Ngoặc mở/đóng lệch nhau trong [text] + dãy số của [text] không thấy trong
/// [output]. Số viết bằng chữ Hán (一二三) không tính — chúng được dịch sang
/// âm Hán Việt là đúng, không phải mất số.
List<TextWarning> _findWarnings(String text, String output) {
  const pairs = {
    '「': '」',
    '『': '』',
    '（': '）',
    '(': ')',
    '【': '】',
    '《': '》',
    '“': '”',
  };
  final openOf = {for (final e in pairs.entries) e.value: e.key};

  final warnings = <TextWarning>[];
  final stack = <({String open, int offset})>[];
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (pairs.containsKey(ch)) {
      stack.add((open: ch, offset: i));
      continue;
    }
    final open = openOf[ch];
    if (open == null) continue;
    if (stack.isEmpty || stack.last.open != open) {
      warnings.add(
        TextWarning(
          kind: TextWarningKind.strayCloseBracket,
          excerpt: ch,
          offset: i,
        ),
      );
    } else {
      stack.removeLast();
    }
  }
  for (final pending in stack) {
    warnings.add(
      TextWarning(
        kind: TextWarningKind.unclosedBracket,
        excerpt: pending.open,
        offset: pending.offset,
      ),
    );
  }

  final remaining = <String, int>{};
  for (final number in _numberRuns(output)) {
    remaining.update(number.text, (n) => n + 1, ifAbsent: () => 1);
  }
  for (final number in _numberRuns(text)) {
    final left = remaining[number.text] ?? 0;
    if (left == 0) {
      warnings.add(
        TextWarning(
          kind: TextWarningKind.missingNumber,
          excerpt: number.text,
          offset: number.offset,
        ),
      );
    } else {
      remaining[number.text] = left - 1;
    }
  }

  warnings.sort((a, b) => a.offset.compareTo(b.offset));
  return warnings;
}

/// Các dãy chữ số liên tiếp (chữ số toàn rộng quy về ASCII để so được).
Iterable<({String text, int offset})> _numberRuns(String s) sync* {
  var i = 0;
  while (i < s.length) {
    if (_digitOf(s.codeUnitAt(i)) == null) {
      i++;
      continue;
    }
    final start = i;
    final buffer = StringBuffer();
    while (i < s.length) {
      final digit = _digitOf(s.codeUnitAt(i));
      if (digit == null) break;
      buffer.write(digit);
      i++;
    }
    yield (text: buffer.toString(), offset: start);
  }
}

String? _digitOf(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return String.fromCharCode(unit);
  if (unit >= 0xFF10 && unit <= 0xFF19) {
    return String.fromCharCode(unit - 0xFF10 + 0x30);
  }
  return null;
}

/// Token phủ [offset] — token cuối cùng có `sourceStart <= offset`.
int _tokenIndexAt(List<Token> tokens, int offset) {
  var lo = 0;
  var hi = tokens.length - 1;
  var result = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (tokens[mid].sourceStart <= offset) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return result;
}

class _TermAccum {
  _TermAccum({required this.meaning, required this.firstStart});

  final String meaning;
  final int firstStart;
  int count = 1;
  final variants = <String, _VariantAccum>{};

  void addVariant(String segmentation, String meaning, int offset) {
    final existing = variants[segmentation];
    if (existing == null) {
      variants[segmentation] = _VariantAccum(
        meaning: meaning,
        firstStart: offset,
      );
    } else {
      existing.count++;
    }
  }
}

class _VariantAccum {
  _VariantAccum({required this.meaning, required this.firstStart});

  final String meaning;
  final int firstStart;
  int count = 1;
}

bool _isUncovered(TokenKind kind) =>
    kind == TokenKind.unmatched || kind == TokenKind.hanViet;

bool _matchesNameShape(UnmatchedChunk chunk, TranslationMode mode) {
  if (chunk.count < minNameOccurrences) return false;
  if (mode == TranslationMode.japanese) {
    return chunk.script == ChunkScript.katakana && chunk.length >= 2;
  }
  return chunk.script == ChunkScript.kanji &&
      chunk.length >= 2 &&
      chunk.length <= 3;
}

/// Cắt [run] thành các đoạn cùng loại chữ rồi cộng dồn vào [accum].
/// [runStart] là offset của [run] trong văn bản nguồn.
void _collectChunks(String run, int runStart, Map<String, _ChunkAccum> accum) {
  var pos = 0;
  while (pos < run.length) {
    final script = _scriptOf(codePointAt(run, pos));
    final segStart = pos;
    var runes = 0;
    do {
      pos += runeLengthAt(run, pos);
      runes++;
    } while (pos < run.length && _scriptOf(codePointAt(run, pos)) == script);
    if (script == null) continue;
    if (script == ChunkScript.hiragana && runes < 2) continue;
    final source = run.substring(segStart, pos);
    final existing = accum[source];
    if (existing == null) {
      accum[source] = _ChunkAccum(
        source: source,
        script: script,
        firstStart: runStart + segStart,
        length: runes,
      );
    } else {
      existing.count++;
    }
  }
}

/// Loại chữ của một code point CJK; null với mọi thứ khác (ASCII, dấu câu,
/// kể cả ・ và các ký hiệu kana không phải chữ).
ChunkScript? _scriptOf(int cp) {
  if (!isCjkCodePoint(cp)) return null;
  switch (charCategoryOf(cp)) {
    case CjkCharCategory.katakana:
      return ChunkScript.katakana;
    case CjkCharCategory.hiragana:
      return ChunkScript.hiragana;
    case CjkCharCategory.kanji:
    case CjkCharCategory.kanjiNumeric:
      return ChunkScript.kanji;
    case CjkCharCategory.space:
    case CjkCharCategory.numeric:
    case CjkCharCategory.alpha:
    case CjkCharCategory.other:
      return null;
  }
}

int _runeCount(String s) {
  var count = 0;
  var i = 0;
  while (i < s.length) {
    count++;
    i += runeLengthAt(s, i);
  }
  return count;
}

int _cjkRuneCount(String s) {
  var count = 0;
  var i = 0;
  while (i < s.length) {
    if (isCjkCodePoint(codePointAt(s, i))) count++;
    i += runeLengthAt(s, i);
  }
  return count;
}

class _ChunkAccum {
  _ChunkAccum({
    required this.source,
    required this.script,
    required this.firstStart,
    required this.length,
  });

  final String source;
  final ChunkScript script;
  final int firstStart;
  final int length;
  int count = 1;
}
