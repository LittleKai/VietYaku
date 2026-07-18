import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary_sync/data/dictionary_sync_api.dart';
import 'package:vietyaku/features/dictionary_sync/data/shared_dictionary_service.dart';
import 'package:vietyaku/features/dictionary_sync/domain/shared_dictionary_entry.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  group('DictionarySyncApi', () {
    test('đăng nhập chỉ chấp nhận tài khoản admin', () async {
      final adminApi = DictionarySyncApi(
        serverUrl: 'https://example.com/api/',
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://example.com/api/auth/login');
          return http.Response(
            jsonEncode({'token': 'jwt-token', 'role': 'admin'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final session = await adminApi.login('admin', 'secret');
      expect(session.username, 'admin');
      expect(session.token, 'jwt-token');

      final userApi = DictionarySyncApi(
        serverUrl: 'https://example.com',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'token': 'jwt-token', 'role': 'user'}),
            200,
          ),
        ),
      );
      expect(
        () => userApi.login('user', 'secret'),
        throwsA(isA<DictionarySyncException>()),
      );
    });

    test('đọc đúng trang delta và cursor', () async {
      final api = DictionarySyncApi(
        serverUrl: 'https://example.com',
        client: MockClient((request) async {
          expect(request.url.queryParameters, {
            'language': 'japanese',
            'cursor': 'cursor-1',
          });
          return http.Response(
            jsonEncode({
              'data': {
                'items': [
                  {
                    'kind': 'vietPhrase',
                    'source': '学校',
                    'target': 'trường học',
                    'revision': 3,
                  },
                ],
                'next_cursor': 'cursor-2',
                'has_more': true,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final page = await api.fetchPage(TranslationMode.japanese, 'cursor-1');
      expect(page.items.single.source, '学校');
      expect(page.items.single.revision, 3);
      expect(page.nextCursor, 'cursor-2');
      expect(page.hasMore, isTrue);
    });

    test('publish gửi JWT và payload theo mode', () async {
      final api = DictionarySyncApi(
        serverUrl: 'https://example.com',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer jwt-token');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['language'], 'chinese');
          expect((body['items'] as List).single, {
            'kind': 'lacViet',
            'source': '李白',
            'target': 'Lý Bạch',
          });
          return http.Response('{}', 200);
        }),
      );
      await api.publish(
        'jwt-token',
        TranslationMode.chinese,
        const SharedDictionaryEntry(
          kind: SharedDictionaryKind.lacViet,
          source: '李白',
          target: 'Lý Bạch',
        ),
      );
    });
  });

  group('SharedDictionaryService', () {
    late Directory temp;
    late SharedDictionaryService service;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('vy_shared_dict');
      service = SharedDictionaryService(AppPaths(temp));
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('merge delta upsert, không nhân đôi và giữ BOM CRLF', () async {
      const first = SharedDictionaryEntry(
        kind: SharedDictionaryKind.vietPhrase,
        source: '学校',
        target: 'trường học',
      );
      expect(await service.applyDelta(TranslationMode.japanese, [first]), 1);
      expect(await service.applyDelta(TranslationMode.japanese, [first]), 0);
      expect(
        await service.applyDelta(TranslationMode.japanese, [
          const SharedDictionaryEntry(
            kind: SharedDictionaryKind.vietPhrase,
            source: '学校',
            target: 'học đường',
          ),
        ]),
        1,
      );

      final file = service.fileFor(
        TranslationMode.japanese,
        SharedDictionaryKind.vietPhrase,
      );
      expect(file.readAsBytesSync().sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(parseEntries(file.readAsStringSync()), {'学校': 'học đường'});
      expect('学校='.allMatches(file.readAsStringSync()).length, 1);
      expect(file.readAsStringSync().endsWith('\r\n'), isTrue);
    });

    test('tách file theo mode và loại từ điển', () async {
      await service.applyDelta(TranslationMode.japanese, [
        const SharedDictionaryEntry(
          kind: SharedDictionaryKind.lacViet,
          source: '学生',
          target: 'học sinh',
        ),
      ]);
      expect(
        service
            .fileFor(TranslationMode.japanese, SharedDictionaryKind.lacViet)
            .existsSync(),
        isTrue,
      );
      expect(
        service
            .fileFor(TranslationMode.chinese, SharedDictionaryKind.lacViet)
            .existsSync(),
        isFalse,
      );
    });

    test('repository chỉ áp shared cho VietPhrase và Lạc Việt', () async {
      final dataDir = Directory(p.join(temp.path, 'data'))
        ..createSync(recursive: true);
      final dictPaths = <DictType, String>{};
      for (final entry in dictFileNames.entries) {
        final file = File(p.join(dataDir.path, entry.value));
        file.writeAsStringSync('');
        dictPaths[entry.key] = file.path;
      }
      File(
        dictPaths[DictType.vietPhrase]!,
      ).writeAsStringSync('\uFEFF学校=VietPhrase local\r\n');
      File(
        dictPaths[DictType.lacViet]!,
      ).writeAsStringSync('\uFEFF学校=Lạc Việt local\r\n');
      await service.applyDelta(TranslationMode.japanese, [
        const SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: '学校',
          target: 'VietPhrase chung',
        ),
        const SharedDictionaryEntry(
          kind: SharedDictionaryKind.lacViet,
          source: '学校',
          target: 'Lạc Việt chung',
        ),
      ]);
      final oldSharedUserDict = File(
        p.join(
          AppPaths(temp).dictionariesDir.path,
          'SharedUserDict_japanese.txt',
        ),
      );
      oldSharedUserDict.writeAsStringSync('\uFEFF学校=không được dùng\r\n');

      final loaded = await DictionaryRepository(
        AppPaths(temp),
      ).loadAll(dictPaths, mode: TranslationMode.japanese);
      expect(loaded.vietPhrase.entries['学校'], 'VietPhrase chung');
      expect(loaded.lacViet.entries['学校'], 'Lạc Việt chung');
      expect(loaded.userDict.entries['学校'], isNull);
    });
  });
}
