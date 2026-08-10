import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tra nghĩa Nhật→Anh qua Jisho (dữ liệu JMdict, API công khai, không cần key).
/// GET https://jisho.org/api/v1/search/words?keyword=...
/// → format thành text hiển thị trong ô Nghĩa. Trả null khi miss/lỗi.
///
/// Chỉ tra được TỪ (không dịch câu) và chỉ tiếng Nhật — mode Trung dùng
/// Google Dịch sang tiếng Anh thay cho nguồn này.
class JishoApi {
  final http.Client _client;

  JishoApi({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> lookup(String word) async {
    try {
      final res = await _client
          .get(
            Uri.https('jisho.org', '/api/v1/search/words', {'keyword': word}),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'VietYaku/1.0',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      final results = data['data'];
      if (results is! List || results.isEmpty) return null;
      // Ưu tiên kết quả trùng đúng từ (kanji hoặc kana), không thì lấy đầu tiên.
      final item =
          results.firstWhere(
                (r) => r is Map && _writings(r).contains(word),
                orElse: () => results.first,
              )
              as Map;
      return format(item);
    } catch (_) {
      return null;
    }
  }

  static Iterable<String> _writings(Map item) sync* {
    final japanese = item['japanese'];
    if (japanese is! List) return;
    for (final form in japanese) {
      if (form is! Map) continue;
      for (final key in const ['word', 'reading']) {
        final value = form[key];
        if (value is String && value.isNotEmpty) yield value;
      }
    }
  }

  /// `取り消し「とりけし」(thường dùng, N5)` + mỗi nghĩa một dòng `- (từ loại) …`.
  static String? format(Map item) {
    final lines = <String>[];
    final japanese = item['japanese'];
    final first = japanese is List && japanese.isNotEmpty
        ? japanese.first
        : null;
    final word = first is Map ? first['word'] : null;
    final reading = first is Map ? first['reading'] : null;
    final tags = [
      if (item['is_common'] == true) 'thường dùng',
      ...?(item['jlpt'] as List?)?.whereType<String>().map(
        (j) => j.replaceFirst('jlpt-n', 'N'),
      ),
    ];
    final header = [
      if (word is String && word.isNotEmpty) word,
      if (reading is String && reading.isNotEmpty) '「$reading」',
      if (tags.isNotEmpty) '(${tags.join(', ')})',
    ].join(' ');
    if (header.isNotEmpty) lines.add(header);

    final senses = item['senses'];
    if (senses is List) {
      for (final sense in senses.take(6)) {
        if (sense is! Map) continue;
        final definitions = (sense['english_definitions'] as List?)
            ?.whereType<String>()
            .toList(growable: false);
        if (definitions == null || definitions.isEmpty) continue;
        final pos = (sense['parts_of_speech'] as List?)
            ?.whereType<String>()
            .join(', ');
        lines.add(
          pos != null && pos.isNotEmpty
              ? '- ($pos) ${definitions.join('; ')}'
              : '- ${definitions.join('; ')}',
        );
      }
    }
    return lines.length <= 1 ? null : lines.join('\n');
  }
}
