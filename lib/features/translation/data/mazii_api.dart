import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tra nghĩa Nhật→Việt qua Mazii (API không chính thức, không cần key).
/// POST https://mazii.net/api/search {dict: javi, type: word, query, ...}
/// → format thành text hiển thị trong ô Nghĩa. Trả null khi miss/lỗi.
class MaziiApi {
  final http.Client _client;

  MaziiApi({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> lookup(String word) async {
    try {
      final res = await _client
          .post(
            Uri.parse('https://mazii.net/api/search'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'VietYaku/1.0',
            },
            body: jsonEncode({
              'dict': 'javi',
              'type': 'word',
              'query': word,
              'limit': 3,
              'page': 1,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map || data['status'] != 200) return null;
      final results = data['data'];
      if (results is! List || results.isEmpty) return null;
      // Ưu tiên kết quả trùng đúng từ, không thì lấy kết quả đầu.
      final item =
          results.firstWhere(
                (r) => r is Map && r['word'] == word,
                orElse: () => results.first,
              )
              as Map;
      return _format(item);
    } catch (_) {
      return null;
    }
  }

  static String? _format(Map item) {
    final lines = <String>[];
    final word = item['word'];
    final phonetic = item['phonetic'];
    final han = item['han'];
    final header = [
      if (word is String && word.isNotEmpty) word,
      if (phonetic is String && phonetic.isNotEmpty) '「$phonetic」',
      if (han is String && han.isNotEmpty) '(Hán: $han)',
    ].join(' ');
    if (header.isNotEmpty) lines.add(header);

    final means = item['means'];
    if (means is List) {
      for (final m in means.take(5)) {
        if (m is! Map) continue;
        final kind = m['kind'];
        final mean = m['mean'];
        if (mean is! String || mean.isEmpty) continue;
        lines.add(
          kind is String && kind.isNotEmpty ? '- ($kind) $mean' : '- $mean',
        );
        final examples = m['examples'];
        if (examples is List && examples.isNotEmpty) {
          final ex = examples.first;
          if (ex is Map) {
            final content = ex['content'];
            final exMean = ex['mean'];
            if (content is String && content.isNotEmpty) {
              lines.add(
                exMean is String && exMean.isNotEmpty
                    ? '  vd: $content → $exMean'
                    : '  vd: $content',
              );
            }
          }
        }
      }
    }
    if (means is! List || lines.length <= 1) {
      final shortMean = item['short_mean'];
      if (shortMean is String && shortMean.isNotEmpty) {
        lines.add('- $shortMean');
      }
    }
    return lines.length <= 1 ? null : lines.join('\n');
  }
}
