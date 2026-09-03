import 'dart:convert';

/// Một từ/cụm con tách ra từ cụm đã tra, đủ ngắn để thành mục từ điển riêng.
///
/// Ví dụ tra `この人こんなにチャラかった` thì `チャラかった` cho ra thân từ
/// `チャラ` — thêm `チャラ` vào từ điển thì engine greedy longest-match mới
/// nhận ra nó trong văn bản khác.
class AiSubEntry {
  final String word;
  final String meaning;

  const AiSubEntry(this.word, this.meaning);

  static AiSubEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final word = (raw['word'] as String?)?.trim();
    final meaning = (raw['meaning'] as String?)?.trim();
    if (word == null || word.isEmpty) return null;
    if (meaning == null || meaning.isEmpty) return null;
    return AiSubEntry(word, meaning);
  }

  Map<String, dynamic> toJson() => {'word': word, 'meaning': meaning};

  @override
  bool operator ==(Object other) =>
      other is AiSubEntry && other.word == word && other.meaning == meaning;

  @override
  int get hashCode => Object.hash(word, meaning);
}

/// Một thành phần trong phần "phân tích từng đoạn".
class AiPart {
  final String part;

  /// Dạng gốc/nguyên thể (VD `チャラかった` → `チャラい`). Rỗng khi không có.
  final String base;
  final String meaning;

  const AiPart(this.part, {this.base = '', required this.meaning});

  static AiPart? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final part = (raw['part'] as String?)?.trim();
    final meaning = (raw['meaning'] as String?)?.trim();
    if (part == null || part.isEmpty) return null;
    return AiPart(
      part,
      base: (raw['base'] as String?)?.trim() ?? '',
      meaning: meaning ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'part': part,
    if (base.isNotEmpty) 'base': base,
    'meaning': meaning,
  };
}

/// Kết quả tra AI đã cấu trúc hoá.
///
/// Lưu vào `AiDict_<mode>.txt` dưới dạng JSON compact (một dòng) thay vì
/// Markdown: ngắn hơn nhiều, không có phần thừa, và đọc lại thì render được
/// đúng bố cục thay vì phải tin vào định dạng AI trả về.
class AiLookupResult {
  final String word;
  final String meaning;
  final String partOfSpeech;
  final List<AiPart> parts;
  final List<AiSubEntry> subEntries;

  const AiLookupResult({
    required this.word,
    required this.meaning,
    this.partOfSpeech = '',
    this.parts = const [],
    this.subEntries = const [],
  });

  /// Body của mục dict: JSON compact, không xuống dòng.
  ///
  /// KHÔNG lưu `sub_entries`: chúng đã được ghi thành mục từ điển riêng ngay
  /// lúc tra, giữ lại đây chỉ làm phình file và khiến ô Nghĩa hiện lại mục
  /// "Đã thêm vào từ điển" mỗi lần mở.
  String toStorageValue() => jsonEncode({
    'meaning': meaning,
    if (partOfSpeech.isNotEmpty) 'pos': partOfSpeech,
    if (parts.isNotEmpty) 'parts': [for (final p in parts) p.toJson()],
  });

  /// Nghĩa ngắn dùng làm value khi chính [word] được thêm vào từ điển engine.
  ///
  /// KHÔNG kèm từ loại: value này được chèn thẳng vào bản dịch, nên đuôi kiểu
  /// `(tính từ/động từ)` chỉ là rác trong câu. Từ loại vẫn còn trong AiDict để
  /// hiển thị ở ô Nghĩa.
  String get shortMeaning => meaning;

  /// Render sang Markdown để hiển thị (ô Nghĩa + dialog).
  String toMarkdown() {
    final sb = StringBuffer();
    sb.writeln('**$meaning**');
    if (partOfSpeech.isNotEmpty) sb.writeln('\n*$partOfSpeech*');

    if (parts.isNotEmpty) {
      sb.writeln('\n**Phân tích**\n');
      for (final p in parts) {
        final head = p.base.isEmpty || p.base == p.part
            ? '**${p.part}**'
            : '**${p.part}** (← ${p.base})';
        sb.writeln(p.meaning.isEmpty ? '- $head' : '- $head — ${p.meaning}');
      }
    }

    if (subEntries.isNotEmpty) {
      sb.writeln('\n**Đã thêm vào từ điển**\n');
      for (final e in subEntries) {
        sb.writeln('- **${e.word}** — ${e.meaning}');
      }
    }
    return sb.toString().trim();
  }

  /// Đọc JSON AI trả về. Chấp nhận cả khi model bọc trong ```json … ``` hoặc
  /// kèm câu dẫn trước/sau — cắt từ `{` đầu tới `}` cuối.
  static AiLookupResult? tryParse(String word, String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final meaning = (decoded['meaning'] as String?)?.trim();
    if (meaning == null || meaning.isEmpty) return null;

    final parts = <AiPart>[];
    if (decoded['parts'] case final List rawParts) {
      for (final raw in rawParts) {
        final part = AiPart.tryParse(raw);
        if (part != null) parts.add(part);
      }
    }

    final subEntries = <AiSubEntry>[];
    if (decoded['sub_entries'] case final List rawSubs) {
      for (final raw in rawSubs) {
        final entry = AiSubEntry.tryParse(raw);
        // Trùng chính cụm đang tra thì bỏ: cụm đó đã có mục riêng rồi.
        if (entry != null && entry.word != word) subEntries.add(entry);
      }
    }

    return AiLookupResult(
      word: word,
      meaning: meaning,
      partOfSpeech: (decoded['pos'] as String?)?.trim() ?? '',
      parts: parts,
      subEntries: subEntries,
    );
  }
}

/// Body của một mục AI đã lưu → Markdown để hiển thị.
///
/// Mục mới lưu JSON; mục cũ lưu thẳng Markdown do AI trả về nên trả nguyên văn.
String aiBodyToMarkdown(String word, String body) {
  final trimmed = body.trimLeft();
  if (!trimmed.startsWith('{')) return body;
  return AiLookupResult.tryParse(word, body)?.toMarkdown() ?? body;
}
