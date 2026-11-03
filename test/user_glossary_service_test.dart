import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/glossary/data/user_glossary_service.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  late Directory tempDir;
  late UserGlossaryService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('user_glossary_test');
    service = UserGlossaryService(tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    try {
      if (Directory('JP').existsSync()) {
        Directory('JP').deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'UserGlossaryService upsert và find hoạt động độc lập theo mode',
    () async {
      expect(await service.find(TranslationMode.japanese, '菜畑小鳥'), isNull);

      await service.upsert(
        TranslationMode.japanese,
        source: '菜畑小鳥',
        target: 'Nabata Kotori',
      );

      final termJp = await service.find(TranslationMode.japanese, '菜畑小鳥');
      expect(termJp, isNotNull);
      expect(termJp!.target, 'Nabata Kotori');
      expect(termJp.createdBy, 'user');

      // Không ảnh hưởng sang mode Trung
      expect(await service.find(TranslationMode.chinese, '菜畑小鳥'), isNull);

      // Cập nhật lại nghĩa
      await service.upsert(
        TranslationMode.japanese,
        source: '菜畑小鳥',
        target: 'Chim nhỏ trên nương',
      );

      final updated = await service.find(TranslationMode.japanese, '菜畑小鳥');
      expect(updated, isNotNull);
      expect(updated!.target, 'Chim nhỏ trên nương');

      final all = await service.readAll(TranslationMode.japanese);
      expect(all.length, 1);
    },
  );

  test(
    'UserGlossaryService đọc được file có BOM và không làm mất dữ liệu',
    () async {
      final file = service.fileFor(TranslationMode.japanese);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '\uFEFF{\r\n'
        '  "name": "User Glossary",\r\n'
        '  "lang": "JP",\r\n'
        '  "terms": [\r\n'
        '    {\r\n'
        '      "source": "りんご",\r\n'
        '      "target": "quả táo",\r\n'
        '      "date_added": "2026-10-30"\r\n'
        '    }\r\n'
        '  ]\r\n'
        '}',
        encoding: utf8,
      );

      final term = await service.find(TranslationMode.japanese, 'りんご');
      expect(term, isNotNull);
      expect(term!.target, 'quả táo');

      // Upsert từ mới giữ nguyên từ cũ
      await service.upsert(
        TranslationMode.japanese,
        source: 'みかん',
        target: 'quả quýt',
      );
      final all = await service.readAll(TranslationMode.japanese);
      expect(all.length, 2);
    },
  );

  test(
    'UserGlossaryService ném FileSystemException khi file bị hỏng để tránh ghi đè mất dữ liệu',
    () async {
      final file = service.fileFor(TranslationMode.japanese);
      await file.parent.create(recursive: true);
      await file.writeAsString('{ invalid json corrupt', encoding: utf8);

      expect(
        () => service.readAll(TranslationMode.japanese),
        throwsA(isA<FileSystemException>()),
      );
      expect(await service.find(TranslationMode.japanese, 'test'), isNull);
      expect(
        () => service.upsert(
          TranslationMode.japanese,
          source: 'test',
          target: 'thử nghiệm',
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'UserGlossaryService ném FileSystemException khi file JSON có root là List hoặc Primitive',
    () async {
      final file = service.fileFor(TranslationMode.japanese);
      await file.parent.create(recursive: true);
      await file.writeAsString('[{"source": "test"}]', encoding: utf8);

      expect(
        () => service.readAll(TranslationMode.japanese),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('UserGlossaryService remove và removeAll xóa đúng các mục', () async {
    await service.upsert(
      TranslationMode.japanese,
      source: 'りんご',
      target: 'quả táo',
    );
    await service.upsert(
      TranslationMode.japanese,
      source: 'みかん',
      target: 'quả quýt',
    );
    await service.upsert(
      TranslationMode.japanese,
      source: 'すいか',
      target: 'dưa hấu',
    );

    expect((await service.readAll(TranslationMode.japanese)).length, 3);

    await service.remove(TranslationMode.japanese, 'みかん');
    final afterOne = await service.readAll(TranslationMode.japanese);
    expect(afterOne.length, 2);
    expect(afterOne.any((t) => t.source == 'みかん'), isFalse);

    await service.removeAll(TranslationMode.japanese, ['りんご', 'すいか']);
    final afterAll = await service.readAll(TranslationMode.japanese);
    expect(afterAll, isEmpty);
  });

  test('UserGlossaryService upsert khi rootDir rỗng là no-op và không tạo folder', () async {
    const emptyService = UserGlossaryService('');
    await emptyService.upsert(
      TranslationMode.japanese,
      source: 'test',
      target: 'thử',
    );
    expect(Directory('JP').existsSync(), isFalse);
  });
}
