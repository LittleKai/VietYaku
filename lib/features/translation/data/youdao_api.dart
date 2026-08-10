import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tra nghĩa Trung→Anh qua từ điển 汉英 của 有道词典 (dict.youdao.com).
///
/// Dùng `jsonapi` với `dicts=[["ce"]]` — endpoint tra từ điển thật, không cần
/// key. KHÔNG dùng `/suggest`: đó là gợi ý ô tìm kiếm, chỉ có headword phổ biến
/// và chỉ hiểu giản thể (時間 phồn thể → 404), tra hụt phần lớn từ.
/// `jsonapi` tự quy phồn→giản (時間 → 时间) và trả pinyin + từ loại.
/// Từ không có trong từ điển → response không có khoá `ce` → null.
class YoudaoApi {
  final http.Client _client;

  YoudaoApi({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> lookup(String word) async {
    try {
      final res = await _client
          .get(
            Uri.https('dict.youdao.com', '/jsonapi', {
              'q': word,
              'dicts': '{"count":99,"dicts":[["ce"]]}',
            }),
            headers: {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return format(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
        word,
      );
    } catch (_) {
      return null;
    }
  }

  /// Tối đa từng này nghĩa — mục nhiều nghĩa (电车 có 7) dài quá thì ô Nghĩa
  /// khó đọc.
  static const _maxSenses = 10;

  /// `取消 「qǔ xiāo」` + mỗi nghĩa một dòng `- (vt.) cancel`.
  static String? format(Map<String, dynamic> json, String word) {
    final words = (json['ce'] as Map<String, dynamic>?)?['word'];
    if (words is! List || words.isEmpty) return null;
    final entry = words.first as Map<String, dynamic>;

    final senses = <String>[];
    for (final trs in (entry['trs'] as List? ?? const [])) {
      final tr = (trs as Map)['tr'] as List?;
      if (tr == null || tr.isEmpty) continue;
      final l = (tr.first as Map)['l'] as Map?;
      final gloss = _joinParts(l?['i']);
      if (gloss == null) continue;
      final pos = l!['pos'] as String?;
      senses.add(pos == null ? '- $gloss' : '- ($pos) $gloss');
      if (senses.length == _maxSenses) break;
    }
    if (senses.isEmpty) return null;

    // `return-phrase` là headword đã quy về giản thể; phồn thể tra ra chữ khác
    // với từ đang tra nên hiện nó lên cho biết.
    final headword = _headword(entry['return-phrase']) ?? word;
    final phone = (entry['phone'] as String?)?.trim();
    final header = phone == null || phone.isEmpty
        ? headword
        : '$headword 「$phone」';
    return '$header\n${senses.join('\n')}';
  }

  /// Một nghĩa bị chẻ thành nhiều mảnh, mỗi từ tra được là một map có `#text`:
  /// `["", {"#text": "call"}, " ", {"#text": "off"}]` → `call off`.
  static String? _joinParts(Object? parts) {
    if (parts is String) return parts.trim().isEmpty ? null : parts.trim();
    if (parts is! List) return null;
    final text = parts
        .map((p) => p is Map ? (p['#text'] as String? ?? '') : '$p')
        .join()
        .trim();
    return text.isEmpty ? null : text;
  }

  static String? _headword(Object? returnPhrase) {
    if (returnPhrase is String) return returnPhrase;
    final i = ((returnPhrase as Map?)?['l'] as Map?)?['i'];
    return i is String ? i : null;
  }
}
