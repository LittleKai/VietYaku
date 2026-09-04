import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary_sync/application/dictionary_sync_controller.dart';
import 'package:vietyaku/features/glossary/application/glossary_service_provider.dart';
import 'package:vietyaku/features/glossary/data/glossary_service.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/glossary/data/glossary_term_queue.dart';
import 'package:vietyaku/features/glossary/domain/glossary_term_change.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

const _glossary =
    '{\r\n'
    '  "name": "Global Glossary",\r\n'
    '  "lang": "JP",\r\n'
    '  "terms": [\r\n'
    '    {\r\n'
    '      "source": "菜畑小鳥",\r\n'
    '      "target": "Nabata Kotori",\r\n'
    '      "kind": "proper_noun",\r\n'
    '      "notes": "",\r\n'
    '      "created_by": "A.I",\r\n'
    '      "date_added": "2026-04-29"\r\n'
    '    }\r\n'
    '  ]\r\n'
    '}';

void main() {
  late Directory temp;
  late SharedPreferences prefs;

  setUp(() async {
    GlossaryService.clearCache();
    temp = await Directory.systemTemp.createTemp('vietyaku_glossary_sync');
    final jpDir = Directory(p.join(temp.path, 'glossary', 'JP'));
    await jpDir.create(recursive: true);
    await File(
      p.join(jpDir.path, GlossaryService.globalGlossaryFileName),
    ).writeAsString(_glossary, encoding: utf8, flush: true);
  });

  tearDown(() async {
    GlossaryService.clearCache();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  GlossaryTermQueue queueOf() => GlossaryTermQueue(AppPaths(temp));

  GlossaryService serviceOf(GlossaryTermQueue queue) => GlossaryService(
    p.join(temp.path, 'glossary'),
    onChanged: (mode, upserts, deletes) =>
        queue.enqueue(mode, upserts: upserts, deletes: deletes),
  );

  test('ghi glossary thì mục vừa đổi được xếp hàng đẩy lên server', () async {
    final queue = queueOf();
    await serviceOf(queue).upsertAll(TranslationMode.japanese, {
      '菜畑小鳥': 'Nabata Kotori mới',
      '白鳥沙羅': 'Shiratori Sara',
      // Mục thiếu nghĩa bị GlossaryService bỏ qua nên không được lên hàng đợi.
      '田中': '',
    });

    final pending = await queue.pending(TranslationMode.japanese);
    expect(
      {for (final change in pending) change.source: change.target},
      {'菜畑小鳥': 'Nabata Kotori mới', '白鳥沙羅': 'Shiratori Sara'},
    );
    expect(pending.every((change) => !change.isDelete), isTrue);
  });

  test('xóa mục glossary thì xếp hàng thao tác delete', () async {
    final queue = queueOf();
    await serviceOf(queue).removeAll(TranslationMode.japanese, ['菜畑小鳥']);

    final pending = await queue.pending(TranslationMode.japanese);
    expect(pending, hasLength(1));
    expect(pending.single.source, '菜畑小鳥');
    expect(pending.single.isDelete, isTrue);
    expect(pending.single.toJson(), {
      'kind': 'glossaryTerm',
      'source': '菜畑小鳥',
      'operation': 'delete',
    });
  });

  test('sửa cùng một từ nhiều lần chỉ giữ giá trị mới nhất', () async {
    final queue = queueOf();
    final service = serviceOf(queue);
    await service.upsert(
      TranslationMode.japanese,
      source: '菜畑小鳥',
      target: 'bản 1',
    );
    await service.upsert(
      TranslationMode.japanese,
      source: '菜畑小鳥',
      target: 'bản 2',
    );

    final pending = await queue.pending(TranslationMode.japanese);
    expect(pending, hasLength(1));
    expect(pending.single.target, 'bản 2');
  });

  test('hàng đợi mỗi mode một file và clear chỉ xóa mode đó', () async {
    final queue = queueOf();
    await queue.enqueue(TranslationMode.japanese, upserts: {'A': 'a'});
    await queue.enqueue(TranslationMode.chinese, upserts: {'B': 'b'});

    await queue.clear(TranslationMode.japanese);
    expect(await queue.pending(TranslationMode.japanese), isEmpty);
    expect(await queue.pending(TranslationMode.chinese), hasLength(1));
  });

  group('auto-publish', () {
    /// Container có phiên admin, `AppPaths` trỏ vào temp và client giả.
    ProviderContainer containerWith(http.Client client) {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) async => AppPaths(temp)),
          syncHttpClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'dictionarySync.admin.username': 'admin',
        'dictionarySync.admin.token': 'jwt-token',
        'glossary.dir': p.join(temp.path, 'glossary'),
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('mục glossary chờ được tính vào ngưỡng tự Update', () async {
      final container = containerWith(MockClient((_) async => http.Response('{}', 200)));
      final queue = GlossaryTermQueue(AppPaths(temp));
      await queue.enqueue(TranslationMode.japanese, upserts: {
        for (var i = 0; i < 4; i++) 'từ$i': 'nghĩa$i',
      });
      await queue.enqueue(TranslationMode.chinese, upserts: {
        for (var i = 0; i < 3; i++) '词$i': 'nghĩa$i',
      });

      expect(
        await container.read(dictionarySyncProvider.notifier).pendingCount(),
        7,
      );
    });

    test('dưới ngưỡng thì không đẩy gì lên server', () async {
      var requests = 0;
      final container = containerWith(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      await GlossaryTermQueue(
        AppPaths(temp),
      ).enqueue(TranslationMode.japanese, upserts: {'từ': 'nghĩa'});

      expect(
        await container.read(dictionarySyncProvider.notifier).maybeAutoPublish(),
        isFalse,
      );
      expect(requests, 0);
    });

    test('đủ ngưỡng thì tự Update và dọn hàng đợi', () async {
      final posted = <String>[];
      final container = containerWith(
        MockClient((request) async {
          posted.add(request.url.path);
          return http.Response('{"data":{"revision":1,"accepted":10}}', 200);
        }),
      );
      final queue = GlossaryTermQueue(AppPaths(temp));
      await queue.enqueue(TranslationMode.japanese, upserts: {
        for (var i = 0; i < 10; i++) 'từ$i': 'nghĩa$i',
      });

      expect(
        await container.read(dictionarySyncProvider.notifier).maybeAutoPublish(),
        isTrue,
      );
      expect(posted, ['/api/glossary/terms/sync']);
      expect(await queue.pending(TranslationMode.japanese), isEmpty);
      expect(
        container.read(dictionarySyncProvider).message,
        contains('10 mục Global Glossary'),
      );
    });

    test('không phải admin thì không bao giờ tự Update', () async {
      SharedPreferences.setMockInitialValues({
        'glossary.dir': p.join(temp.path, 'glossary'),
      });
      prefs = await SharedPreferences.getInstance();
      var requests = 0;
      final container = containerWith(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      await GlossaryTermQueue(AppPaths(temp)).enqueue(
        TranslationMode.japanese,
        upserts: {for (var i = 0; i < 20; i++) 'từ$i': 'nghĩa$i'},
      );

      expect(
        await container.read(dictionarySyncProvider.notifier).maybeAutoPublish(),
        isFalse,
      );
      expect(requests, 0);
    });

    test('ghi hàng loạt qua provider chỉ xếp hàng, không tự Update', () async {
      final posted = <String>[];
      final container = containerWith(
        MockClient((request) async {
          posted.add(request.url.path);
          return http.Response('{"data":{}}', 200);
        }),
      );
      // Ghi 12 mục một lần: quá ngưỡng, nhưng là ghi hàng loạt nên phải chờ
      // admin tự bấm Update — đúng quy ước của stageLocalEditsBulk.
      await container.read(glossaryServiceProvider).upsertAll(
        TranslationMode.japanese,
        {for (var i = 0; i < 12; i++) '菜畑小鳥$i': 'Nabata $i'},
      );

      expect(posted, isEmpty);
      expect(
        await GlossaryTermQueue(AppPaths(temp)).pending(TranslationMode.japanese),
        hasLength(12),
      );
    });
  });

  test('mục sai định dạng bị loại trước khi lên server', () async {
    // Server từ chối cả lô nếu một mục sai, mà lô hỏng thì hàng đợi không bao
    // giờ trống — nên `=` trong key và xuống dòng trong nghĩa phải bị chặn ngay.
    expect(
      const GlossaryTermChange(source: 'a=b', target: 'x').isValid,
      isFalse,
    );
    expect(
      const GlossaryTermChange(source: '学校', target: 'a\nb').isValid,
      isFalse,
    );
    expect(const GlossaryTermChange(source: '学校').isValid, isFalse);
    expect(
      const GlossaryTermChange(source: '学校', isDelete: true).isValid,
      isTrue,
    );

    final queue = queueOf();
    await queue.enqueue(
      TranslationMode.japanese,
      upserts: {'a=b': 'x', '学校': 'trường học'},
    );
    final pending = await queue.pending(TranslationMode.japanese);
    expect(pending.map((change) => change.source), ['学校']);
  });
}
