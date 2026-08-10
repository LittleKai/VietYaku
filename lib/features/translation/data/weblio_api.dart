import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tra nghĩa Nhật→Trung qua từ điển 日中中日辞典 của Weblio (cjjc.weblio.jp).
///
/// Weblio không có API công khai nên phải crawl, nhưng đọc thẻ
/// `<meta name="description">` thay vì thân trang: Weblio đã tóm tắt sẵn
/// 中国語訳 + ピンイン ở đó, còn thân trang đầy quảng cáo và đổi layout liên tục.
/// Đánh đổi: mô tả bị cắt ~200 ký tự nên mục dài (chiều Trung→Nhật) mất phần
/// đuôi. Trả null khi miss/lỗi.
class WeblioApi {
  final http.Client _client;

  WeblioApi({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> lookup(String word) async {
    try {
      final res = await _client
          .get(
            Uri.https('cjjc.weblio.jp', '/content/$word'),
            headers: {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return format(utf8.decode(res.bodyBytes), word);
    } catch (_) {
      return null;
    }
  }

  static final _meta = RegExp(
    r'<meta[^>]*name="description"[^>]*content="([^"]*)"',
  );

  /// Weblio dồn hết nhãn vào một dòng liền — tách dòng theo các nhãn này.
  static final _labels = RegExp('(読み方|中国語訳|ピンイン|中国語品詞|対訳の関係|日本語での説明|用例)');

  /// `勉強の意味や日本語訳。中国語訳功课ピンインgōngkè - 約160万語…`
  /// → `中国語訳 功课` / `ピンイン gōngkè`.
  static String? format(String html, String word) {
    final match = _meta.firstMatch(html);
    if (match == null) return null;
    var text = _unescape(match.group(1)!);
    // Bỏ đuôi giới thiệu site rồi bỏ tiền tố nhắc lại chính từ đang tra.
    final tail = text.indexOf(' - 約');
    if (tail > 0) text = text.substring(0, tail);
    text = text
        .replaceFirst(RegExp('^${RegExp.escape(word)}の(?:意味や日本語訳|中国語訳)。'), '')
        .replaceAllMapped(_labels, (m) => '\n${m[0]} ')
        .trim();
    return text.isEmpty ? null : text;
  }

  static String _unescape(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
