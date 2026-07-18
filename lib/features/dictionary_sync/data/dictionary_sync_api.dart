import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../translation/domain/translation_engine.dart';
import '../domain/shared_dictionary_entry.dart';

class DictionarySyncException implements Exception {
  final int? statusCode;
  final String message;

  const DictionarySyncException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class AdminSession {
  final String username;
  final String token;

  const AdminSession({required this.username, required this.token});
}

class DictionarySyncPage {
  final List<SharedDictionaryEntry> items;
  final String nextCursor;
  final bool hasMore;

  const DictionarySyncPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}

class DictionarySyncApi {
  final String serverUrl;
  final http.Client client;

  DictionarySyncApi({required this.serverUrl, required this.client});

  Uri _uri(String path, [Map<String, String>? query]) {
    var base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
    return Uri.parse('$base/api$path').replace(queryParameters: query);
  }

  Future<AdminSession> login(String username, String password) async {
    final response = await client
        .post(
          _uri('/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, body);
    }
    if (body['role'] != 'admin') {
      throw const DictionarySyncException(
        'Tài khoản không có quyền quản trị.',
        statusCode: 403,
      );
    }
    final token = body['token'];
    if (token is! String || token.isEmpty) {
      throw const DictionarySyncException(
        'Server không trả về phiên đăng nhập.',
      );
    }
    return AdminSession(username: username, token: token);
  }

  Future<DictionarySyncPage> fetchPage(
    TranslationMode mode,
    String cursor,
  ) async {
    final query = <String, String>{'language': mode.name};
    if (cursor.isNotEmpty) query['cursor'] = cursor;
    final response = await client
        .get(_uri('/glossary/sync', query))
        .timeout(const Duration(seconds: 20));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, body);
    }
    final data = body['data'];
    if (data is! Map<String, dynamic> || data['items'] is! List) {
      throw const DictionarySyncException('Dữ liệu đồng bộ không hợp lệ.');
    }
    return DictionarySyncPage(
      items: [
        for (final item in data['items'] as List)
          SharedDictionaryEntry.fromJson(item as Map<String, dynamic>),
      ],
      nextCursor: data['next_cursor'] as String? ?? cursor,
      hasMore: data['has_more'] as bool? ?? false,
    );
  }

  Future<void> publish(
    String token,
    TranslationMode mode,
    SharedDictionaryEntry entry,
  ) async {
    final response = await client
        .post(
          _uri('/glossary/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'language': mode.name,
            'items': [entry.toJson()],
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, body);
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  static DictionarySyncException _apiError(
    int statusCode,
    Map<String, dynamic> body,
  ) {
    final serverMessage = body['msg'];
    final message = switch (statusCode) {
      401 => 'Phiên đăng nhập đã hết hạn.',
      403 => 'Tài khoản không có quyền cập nhật từ điển chung.',
      429 => 'Server đang giới hạn yêu cầu, hãy thử lại sau.',
      _ when serverMessage is String && serverMessage.isNotEmpty =>
        serverMessage,
      _ => 'Không thể kết nối dịch vụ từ điển (HTTP $statusCode).',
    };
    return DictionarySyncException(message, statusCode: statusCode);
  }
}
