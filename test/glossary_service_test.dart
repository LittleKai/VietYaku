import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vietyaku/features/glossary/data/glossary_service.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

/// Payload y hệt tool Python: UTF-8 không BOM, indent 2, CRLF, không newline cuối.
const _jpGlossary =
    '{\r\n'
    '  "name": "Global Glossary",\r\n'
    '  "lang": "JP",\r\n'
    '  "is_shared": true,\r\n'
    '  "is_published": false,\r\n'
    '  "public_id": "",\r\n'
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
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vietyaku_glossary');
    final jpDir = Directory(p.join(root.path, 'JP'));
    await jpDir.create(recursive: true);
    await File(
      p.join(jpDir.path, GlossaryService.globalGlossaryFileName),
    ).writeAsString(_jpGlossary, encoding: utf8, flush: true);
  });

  tearDown(() async => root.delete(recursive: true));

  test('hasGlossaryFor chỉ đúng khi có file của ngôn ngữ đó', () {
    final service = GlossaryService(root.path);
    expect(service.hasGlossaryFor(TranslationMode.japanese), isTrue);
    expect(service.hasGlossaryFor(TranslationMode.chinese), isFalse);
    expect(
      const GlossaryService('').hasGlossaryFor(TranslationMode.japanese),
      isFalse,
    );
  });

  test('find khớp source bỏ qua hoa/thường và khoảng trắng', () async {
    final service = GlossaryService(root.path);
    final term = await service.find(TranslationMode.japanese, ' 菜畑小鳥 ');
    expect(term, isNotNull);
    expect(term!.target, 'Nabata Kotori');
    expect(term.createdBy, 'A.I');
    expect(
      await service.find(TranslationMode.japanese, '存在しない'),
      isNull,
    );
  });

  test('upsert mục có sẵn: đổi target + created_by, giữ các field khác', () async {
    final service = GlossaryService(root.path);
    await service.upsert(
      TranslationMode.japanese,
      source: '菜畑小鳥',
      target: 'Nabata Kotori (mới)',
    );

    final term = (await service.find(TranslationMode.japanese, '菜畑小鳥'))!;
    expect(term.target, 'Nabata Kotori (mới)');
    expect(term.createdBy, 'user');
    expect(term.kind, 'proper_noun');
    expect(term.dateAdded, '2026-04-29');

    final payload =
        jsonDecode(await service.fileFor(TranslationMode.japanese).readAsString())
            as Map<String, dynamic>;
    expect(payload['is_shared'], isTrue);
    expect(payload['name'], 'Global Glossary');
    expect((payload['terms'] as List).length, 1);
  });

  test('upsert mục mới: thêm cuối danh sách với created_by = user', () async {
    final service = GlossaryService(root.path);
    await service.upsert(
      TranslationMode.japanese,
      source: '箸尾拓海',
      target: 'Hashio Takumi',
    );

    final terms =
        (jsonDecode(
              await service.fileFor(TranslationMode.japanese).readAsString(),
            )
            as Map<String, dynamic>)['terms']
        as List;
    expect(terms.length, 2);
    final added = terms.last as Map<String, dynamic>;
    expect(added['source'], '箸尾拓海');
    expect(added['target'], 'Hashio Takumi');
    expect(added['kind'], 'proper_noun');
    expect(added['notes'], '');
    expect(added['created_by'], 'user');
    expect(added['date_added'], GlossaryService.todayStamp());
    expect(added.keys.toList(), [
      'source',
      'target',
      'kind',
      'notes',
      'created_by',
      'date_added',
    ]);
  });

  test('ghi lại đúng định dạng của tool Python (CRLF, indent 2, không BOM)', () async {
    final service = GlossaryService(root.path);
    await service.upsert(
      TranslationMode.japanese,
      source: '箸尾拓海',
      target: 'Hashio Takumi',
    );

    final bytes = await service
        .fileFor(TranslationMode.japanese)
        .readAsBytes();
    expect(bytes.first, '{'.codeUnitAt(0), reason: 'không có BOM');
    expect(bytes.last, '}'.codeUnitAt(0), reason: 'không có newline cuối file');

    final text = utf8.decode(bytes);
    expect(text.contains('\n'), isTrue);
    expect(RegExp(r'(?<!\r)\n').hasMatch(text), isFalse, reason: 'toàn CRLF');
    expect(text.contains('\r\n  "name": "Global Glossary",'), isTrue);
    expect(text.contains('菜畑小鳥'), isTrue, reason: 'không escape non-ASCII');
  });

  test('removeAll xóa đúng mục theo source key không phân biệt hoa thường', () async {
    final service = GlossaryService(root.path);
    await service.upsert(
      TranslationMode.japanese,
      source: '箸尾拓海',
      target: 'Hashio Takumi',
    );
    expect((await service.readAll(TranslationMode.japanese)).length, 2);

    await service.removeAll(TranslationMode.japanese, ['菜畑小鳥']);
    final terms = await service.readAll(TranslationMode.japanese);
    expect(terms.length, 1);
    expect(terms.single.source, '箸尾拓海');
  });
}
