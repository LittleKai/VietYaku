import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client Google Translate không cần key:
/// 1. Endpoint gtx (`translate.googleapis.com/translate_a/single`) — nhanh,
///    dịch cả đoạn, nhưng Google có thể chặn bất kỳ lúc nào.
/// 2. Fallback: crawl bản mobile web (`translate.google.com/m`) — HTML tĩnh,
///    parse `<div class="result-container">`.
class GoogleTranslateClient {
  final http.Client _client;

  GoogleTranslateClient({http.Client? client})
      : _client = client ?? http.Client();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  /// Dịch [text] sang tiếng Việt. [sourceLang]: 'ja', 'zh-CN'…
  /// Trả null khi cả hai đường đều thất bại.
  Future<String?> translate(String text, {required String sourceLang}) async {
    if (text.trim().isEmpty) return null;
    return await _viaGtx(text, sourceLang) ?? await _viaMobileWeb(text, sourceLang);
  }

  Future<String?> _viaGtx(String text, String sourceLang) async {
    try {
      final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': sourceLang,
        'tl': 'vi',
        'dt': 't',
        'q': text,
      });
      final res = await _client.get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      // Dạng [[["dịch","gốc",...], ...], ...] — ghép mọi segment đầu.
      if (data is! List || data.isEmpty || data[0] is! List) return null;
      final buffer = StringBuffer();
      for (final seg in data[0] as List) {
        if (seg is List && seg.isNotEmpty && seg[0] is String) {
          buffer.write(seg[0] as String);
        }
      }
      final out = buffer.toString().trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _viaMobileWeb(String text, String sourceLang) async {
    try {
      final uri = Uri.https('translate.google.com', '/m', {
        'sl': sourceLang,
        'tl': 'vi',
        'q': text,
      });
      final res = await _client.get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final html = utf8.decode(res.bodyBytes);
      final m = RegExp(r'class="result-container">([\s\S]*?)</div>')
          .firstMatch(html);
      if (m == null) return null;
      final out = _unescapeHtml(m.group(1)!).trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static String _unescapeHtml(String s) => s
      .replaceAll('<br>', '\n')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
