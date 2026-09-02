import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vietyaku/features/translation/data/mazii_api.dart';

http.Client _mock(List<Map<String, dynamic>> data) => MockClient(
  (_) async => http.Response(
    jsonEncode({'status': 200, 'data': data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
);

void main() {
  // `/api/search` bỏ qua tham số `dict`: hỏi `cnvi` vẫn trả mục của từ điển
  // Nhật. Nhận bừa thì mode Trung lưu vào OnlineDict nghĩa của một từ tiếng
  // Nhật khác hẳn — cả 35 mục OnlineDict_chinese thật đều dính lỗi này.
  group('Mazii mode Trung không nhận kết quả từ điển Nhật', () {
    test('bỏ kết quả có cách đọc kana khi tra cnvi', () async {
      final api = MaziiApi(
        client: _mock([
          {
            'word': '幸福',
            'phonetic': 'こうふく',
            'means': [
              {'kind': 'n', 'mean': 'happiness'},
            ],
          },
        ]),
      );

      expect(await api.lookup('幸福', dict: 'cnvi'), isNull);
    });

    test('vẫn nhận kết quả kana khi tra javi', () async {
      final api = MaziiApi(
        client: _mock([
          {
            'word': '幸福',
            'phonetic': 'こうふく',
            'means': [
              {'kind': 'n', 'mean': 'hạnh phúc'},
            ],
          },
        ]),
      );

      final result = await api.lookup('幸福', dict: 'javi');
      expect(result, contains('こうふく'));
      expect(result, contains('hạnh phúc'));
    });

    test('nhận kết quả cnvi thật (pinyin, không kana)', () async {
      final api = MaziiApi(
        client: _mock([
          {
            'word': '幸福',
            'pinyin': 'xìng fú',
            'means': [
              {'kind': 'n', 'mean': 'hạnh phúc'},
            ],
          },
        ]),
      );

      final result = await api.lookup('幸福', dict: 'cnvi');
      expect(result, contains('xìng fú'));
      expect(result, contains('hạnh phúc'));
    });

    test('không có phonetic thì không bị chặn nhầm', () async {
      final api = MaziiApi(
        client: _mock([
          {
            'word': '温斯',
            'means': [
              {'mean': 'Wins'},
            ],
          },
        ]),
      );

      expect(await api.lookup('温斯', dict: 'cnvi'), isNotNull);
    });
  });
}
