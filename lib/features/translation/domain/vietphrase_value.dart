/// Từ loại gắn với từng tầng nghĩa VietPhrase.
///
/// Mã lưu trong file giữ ngắn gọn và tương thích dữ liệu QuickTranslator cũ.
enum VietPhrasePartOfSpeech {
  none('', 'Không phân loại', ''),
  noun('n', 'Danh từ', 'DT'),
  verb('v', 'Động từ', 'ĐT'),
  adjective('adj', 'Tính từ', 'TT'),
  adverb('adv', 'Trạng từ', 'TrT'),
  pronoun('pron', 'Đại từ', 'ĐạiT'),
  numeral('num', 'Số từ', 'ST'),
  preposition('prep', 'Giới từ', 'GT'),
  conjunction('conj', 'Liên từ', 'LT'),
  particle('part', 'Trợ từ', 'TrợT'),
  auxiliary('aux', 'Trợ động từ', 'TrĐT'),
  interjection('int', 'Thán từ', 'ThánT'),
  expression('exp', 'Cụm từ / thành ngữ', 'Cụm');

  const VietPhrasePartOfSpeech(this.code, this.label, this.shortLabel);

  final String code;
  final String label;
  final String shortLabel;

  static VietPhrasePartOfSpeech? tryParseCode(String raw) {
    final code = raw.trim().toLowerCase();
    for (final value in values.skip(1)) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// Một tầng nghĩa, có thể chứa nhiều cách dịch đồng nghĩa ngăn bởi `/`.
class VietPhraseMeaning {
  const VietPhraseMeaning({
    required this.text,
    this.partOfSpeech = VietPhrasePartOfSpeech.none,
  });

  /// Các cách dịch của cùng tầng ở dạng `cách 1/cách 2/...`.
  final String text;
  final VietPhrasePartOfSpeech partOfSpeech;

  List<String> get alternatives => text
      .split('/')
      .map((alternative) => alternative.trim())
      .where((alternative) => alternative.isNotEmpty)
      .toList(growable: false);

  String get primaryText => alternatives.firstOrNull ?? '';

  /// Dạng gọn dùng trong panel đa nghĩa, VD `(n) ký ức/hồi ức`.
  String get displayText => partOfSpeech == VietPhrasePartOfSpeech.none
      ? text
      : '(${partOfSpeech.code}) $text';

  /// Dạng gọn dùng trong panel một nghĩa: chỉ lấy cách dịch đầu của tầng đầu.
  String get displayPrimaryText =>
      partOfSpeech == VietPhrasePartOfSpeech.none || primaryText.isEmpty
      ? primaryText
      : '(${partOfSpeech.code}) $primaryText';
}

final _leadingMarker = RegExp(r'^\s*\(([^()]+)\)\s*');

/// Đọc value VietPhrase cũ lẫn mới thành các tầng nghĩa.
///
/// Dấu `/` thông thường chỉ ngăn các cách dịch trong cùng một tầng. Marker số
/// (`/(2)/`, `/(2)x`) mở tầng mới. Marker từ loại ở đầu phân loại tầng đầu;
/// marker từ loại sau một tầng đã có nội dung vừa mở tầng mới vừa phân loại nó.
/// Ngoặc không phải marker đã biết vẫn là nội dung bình thường.
List<VietPhraseMeaning> parseVietPhraseValue(String value) {
  final meanings = <VietPhraseMeaning>[];
  final alternatives = <String>[];
  var activePartOfSpeech = VietPhrasePartOfSpeech.none;

  void flushMeaning() {
    if (alternatives.isEmpty) return;
    meanings.add(
      VietPhraseMeaning(
        text: alternatives.join('/'),
        partOfSpeech: activePartOfSpeech,
      ),
    );
    alternatives.clear();
  }

  for (final rawPart in value.split('/')) {
    var part = rawPart.trim();
    if (part.isEmpty) continue;

    while (part.isNotEmpty) {
      final match = _leadingMarker.firstMatch(part);
      if (match == null) break;
      final marker = match.group(1)!.trim();
      final number = int.tryParse(marker);
      final partOfSpeech = VietPhrasePartOfSpeech.tryParseCode(marker);

      if (number != null) {
        flushMeaning();
        activePartOfSpeech = VietPhrasePartOfSpeech.none;
      } else if (partOfSpeech != null) {
        // Nếu tầng hiện tại đã có nội dung thì marker POS này bắt đầu tầng sau.
        // Nếu vừa có marker số thì danh sách đang rỗng, nên POS chỉ chú thích
        // tầng đang chờ thay vì tạo thêm một tầng rỗng.
        flushMeaning();
        activePartOfSpeech = partOfSpeech;
      } else {
        break;
      }

      part = part.substring(match.end).trim();
    }

    if (part.isNotEmpty) alternatives.add(part);
  }

  flushMeaning();
  return meanings;
}

/// Ghi một format duy nhất, marker luôn đứng riêng:
/// `(n)/cách 1/cách 2/(2)/(v)/cách 3`.
String encodeVietPhraseValue(Iterable<VietPhraseMeaning> meanings) {
  final normalized = meanings
      .map(
        (meaning) => VietPhraseMeaning(
          text: meaning.alternatives.join('/'),
          partOfSpeech: meaning.partOfSpeech,
        ),
      )
      .where((meaning) => meaning.text.isNotEmpty)
      .toList();
  if (normalized.isEmpty) return '';

  final buffer = StringBuffer();
  for (var i = 0; i < normalized.length; i++) {
    final meaning = normalized[i];
    if (i > 0) buffer.write('/(${i + 1})/');
    if (meaning.partOfSpeech != VietPhrasePartOfSpeech.none) {
      buffer.write('(${meaning.partOfSpeech.code})/');
    }
    buffer.write(meaning.text);
  }
  return buffer.toString();
}

String firstVietPhraseMeaning(String value) {
  final meanings = parseVietPhraseValue(value);
  return meanings.isEmpty ? '' : meanings.first.primaryText;
}

/// Gom tất cả các cách dịch sạch (đã lọc bỏ marker số tầng và marker từ loại)
/// từ tất cả các tầng nghĩa, nối bằng dấu `/`.
/// VD: `(n)/ký ức/hồi ức/(2)/(v)/nhớ lại` -> `ký ức/hồi ức/nhớ lại`.
String allVietPhraseMeaningsClean(String value) {
  final meanings = parseVietPhraseValue(value);
  if (meanings.isEmpty) return value.trim();
  final allAlternatives = meanings
      .expand((m) => m.alternatives)
      .map((alt) => alt.trim())
      .where((alt) => alt.isNotEmpty)
      .toList();
  return allAlternatives.isEmpty ? '' : allAlternatives.join('/');
}

/// Đưa mọi biến thể marker cũ về format duy nhất mà dialog VietPhrase ghi.
String normalizeVietPhraseValue(String value) =>
    encodeVietPhraseValue(parseVietPhraseValue(value));

/// Chuyển đổi định dạng VietPhrase sang định dạng hiển thị / lưu của Lạc Việt (escaped `\n\t`).
///
/// - Nếu có từ loại:
///   `- (danh từ) cách 1; cách 2\n- (động từ) cách 3`
/// - Nếu đa tầng không từ loại:
///   `- cách 1\n- cách 2`
/// - Nếu chỉ có 1 tầng không từ loại:
///   `cách 1; cách 2`
String convertVietPhraseToLacVietFormat(String vpValue) {
  final meanings = parseVietPhraseValue(vpValue);
  if (meanings.isEmpty) return vpValue.trim();

  final hasPos = meanings.any(
    (m) => m.partOfSpeech != VietPhrasePartOfSpeech.none,
  );
  final isMultiTier = meanings.length > 1;

  if (hasPos || isMultiTier) {
    final lines = <String>[];
    for (final meaning in meanings) {
      final altText = meaning.alternatives.join('; ');
      if (meaning.partOfSpeech != VietPhrasePartOfSpeech.none) {
        final posLabel = meaning.partOfSpeech.label.toLowerCase();
        if (altText.isNotEmpty) {
          lines.add('- ($posLabel) $altText');
        } else {
          lines.add('- ($posLabel)');
        }
      } else {
        if (isMultiTier) {
          lines.add('- $altText');
        } else {
          lines.add(altText);
        }
      }
    }
    return lines.join(r'\n');
  }

  return meanings.first.alternatives.join('; ');
}

/// Chuyển value VietPhrase sang dạng hiển thị trong panel Nghĩa / popup tra nhanh:
/// các cách dịch trong cùng tầng và giữa các tầng ngăn cách bởi `; `.
/// VD: `kết thúc/giải quyết/hoàn thành` -> `kết thúc; giải quyết; hoàn thành`.
/// `(n)/ký ức/hồi ức/(2)/(v)/nhớ lại` -> `(n) ký ức; hồi ức; (v) nhớ lại`.
String formatVietPhraseForLookup(String value) {
  final meanings = parseVietPhraseValue(value);
  if (meanings.isEmpty) return value.replaceAll('/', '; ');
  return meanings.map((meaning) {
    final altText = meaning.alternatives.join('; ');
    final text = altText.isNotEmpty ? altText : meaning.text;
    if (meaning.partOfSpeech == VietPhrasePartOfSpeech.none) {
      return text;
    }
    return '(${meaning.partOfSpeech.code}) $text';
  }).join('; ');
}


/// Kiểu hiển thị VietPhrase đa nghĩa trong tab đa nghĩa.
enum MultiMeaningDisplayMode {
  /// Phân cấp thị giác màu sắc & định dạng (Mặc định).
  /// Nghĩa tầng 1 in đậm/màu chữ chính; Nghĩa tầng 2 trở đi mang màu sắc riêng biệt; nhãn từ loại nổi bật.
  visualHierarchy(
    'visualHierarchy',
    'Phân cấp màu sắc',
    'Nghĩa chính nổi bật, nghĩa tầng 2 trở đi mang màu sắc riêng biệt, nhãn từ loại nổi bật.',
  ),

  /// Phân tầng bằng ký hiệu số & dấu ngăn cách rõ ràng.
  /// [① [DT] ký ức/hồi ức ‖ ② [ĐT] nhớ lại]
  tieredNumbered(
    'tieredNumbered',
    'Đánh số phân tầng',
    'Phân biệt rõ ràng giữa từ đồng nghĩa (/) và tầng nghĩa khác nhau (①, ②, ‖).',
  ),

  /// Kiểu QuickTranslator truyền thống: [nghĩa1/nghĩa2/nghĩa3]
  classic(
    'classic',
    'Cổ điển QuickTranslator',
    'Tất cả các nghĩa và tầng nghĩa nối nhau bằng dấu gạch chéo [/].',
  );

  const MultiMeaningDisplayMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static MultiMeaningDisplayMode fromKey(String? key) {
    for (final mode in values) {
      if (mode.key == key) return mode;
    }
    return visualHierarchy;
  }
}

/// Ký hiệu số khoanh tròn: 1 → ①, 2 → ②, ...
String circledNumber(int n) {
  if (n >= 1 && n <= 20) {
    return String.fromCharCode(0x2460 + n - 1);
  }
  return '($n)';
}

/// Chỉ số trên (superscript): 2 → ², 3 → ³, ...
String superscriptNumber(int n) {
  const digits = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];
  if (n < 0) return '$n';
  if (n < 10) return digits[n];
  return n.toString().split('').map((c) {
    final d = int.tryParse(c);
    return d != null ? digits[d] : c;
  }).join();
}
