import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vietyaku/features/glossary/application/glossary_sync_controller.dart';
import 'package:vietyaku/features/glossary/data/glossary_service.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

GlossarySyncRow _row(
  String source,
  String target, {
  String? otherTarget,
  String createdBy = '',
}) => GlossarySyncRow(
  source: source,
  target: target,
  otherTarget: otherTarget,
  createdBy: createdBy,
);

const _glossary =
    '{\r\n'
    '  "name": "Global Glossary",\r\n'
    '  "lang": "JP",\r\n'
    '  "terms": [\r\n'
    '    {\r\n'
    '      "source": "菜畑小鳥",\r\n'
    '      "target": "Nabata Kotori",\r\n'
    '      "kind": "proper_noun",\r\n'
    '      "notes": "ghi chú",\r\n'
    '      "created_by": "A.I",\r\n'
    '      "date_added": "2026-04-29"\r\n'
    '    }\r\n'
    '  ]\r\n'
    '}';

void main() {
  group('filterGlossarySyncRows', () {
    final rows = [
      _row('菜畑小鳥', 'Nabata Kotori', createdBy: 'A.I'),
      _row('白鳥沙羅', 'Shiratori Sara', createdBy: 'user'),
      _row(
        '箸尾拓海',
        'Hashio Takumi',
        otherTarget: 'Hashio Takuya',
        createdBy: 'A.I',
      ),
      _row(
        '田中',
        'Tanaka',
        otherTarget: 'Tanaka',
        createdBy: 'migration',
      ),
    ];

    test('Không trùng: chỉ giữ mục bên kia chưa có', () {
      final result = filterGlossarySyncRows(
        rows,
        duplicateFilter: DuplicateFilter.notDuplicated,
        createdByAiOnly: false,
      );
      expect(result.map((r) => r.source), ['菜畑小鳥', '白鳥沙羅']);
    });

    test('Khác nghĩa (Có trùng): chỉ giữ mục bên kia đã có nhưng khác giá trị (bỏ qua mục giống hệt)', () {
      final result = filterGlossarySyncRows(
        rows,
        duplicateFilter: DuplicateFilter.duplicated,
        createdByAiOnly: false,
      );
      expect(result.map((r) => r.source), ['箸尾拓海']);
      expect(result.single.isIdentical, isFalse);
    });

    test('Giống hệt: chỉ giữ mục đã có ở cả 2 bên và giá trị y hệt', () {
      final result = filterGlossarySyncRows(
        rows,
        duplicateFilter: DuplicateFilter.identical,
        createdByAiOnly: false,
      );
      expect(result.map((r) => r.source), ['田中']);
      expect(result.single.isIdentical, isTrue);
    });

    test('Tất cả: giữ toàn bộ các mục bất kể trùng hay giống hệt', () {
      final result = filterGlossarySyncRows(
        rows,
        duplicateFilter: DuplicateFilter.all,
        createdByAiOnly: false,
      );
      expect(result.length, 4);
    });

    test('created_by = A.I lọc bỏ user/migration', () {
      final result = filterGlossarySyncRows(
        rows,
        duplicateFilter: DuplicateFilter.notDuplicated,
        createdByAiOnly: true,
      );
      expect(result.map((r) => r.source), ['菜畑小鳥']);
    });

    test('tìm kiếm khớp cả từ nguồn lẫn nghĩa, không phân biệt hoa thường', () {
      expect(
        filterGlossarySyncRows(
          rows,
          duplicateFilter: DuplicateFilter.notDuplicated,
          createdByAiOnly: false,
          search: 'shiratori',
        ).single.source,
        '白鳥沙羅',
      );
      expect(
        filterGlossarySyncRows(
          rows,
          duplicateFilter: DuplicateFilter.notDuplicated,
          createdByAiOnly: false,
          search: '菜畑',
        ).single.source,
        '菜畑小鳥',
      );
    });

    test('isCreatedByAi chấp nhận "A.I" và "ai", loại "user"', () {
      expect(_row('a', 'b', createdBy: 'A.I').isCreatedByAi, isTrue);
      expect(_row('a', 'b', createdBy: ' ai ').isCreatedByAi, isTrue);
      expect(_row('a', 'b', createdBy: 'User').isCreatedByAi, isFalse);
      expect(_row('a', 'b').isCreatedByAi, isFalse);
    });
  });

  group('GlossaryService.upsertAll', () {
    late Directory root;
    late GlossaryService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('vietyaku_glossary_sync');
      final jpDir = Directory(p.join(root.path, 'JP'));
      await jpDir.create(recursive: true);
      await File(
        p.join(jpDir.path, GlossaryService.globalGlossaryFileName),
      ).writeAsString(_glossary, encoding: utf8, flush: true);
      service = GlossaryService(root.path);
    });

    tearDown(() async => root.delete(recursive: true));

    test('ghi nhiều mục trong một lần: vừa thêm mới vừa ghi đè', () async {
      await service.upsertAll(TranslationMode.japanese, {
        '菜畑小鳥': 'Nabata Kotori (sửa)',
        '白鳥沙羅': 'Shiratori Sara',
        '箸尾拓海': 'Hashio Takumi',
      });

      final terms = await service.readAll(TranslationMode.japanese);
      expect(terms.length, 3);

      final updated = terms.firstWhere((t) => t.source == '菜畑小鳥');
      expect(updated.target, 'Nabata Kotori (sửa)');
      expect(updated.createdBy, 'user');
      expect(updated.notes, 'ghi chú', reason: 'giữ nguyên field cũ');
      expect(updated.dateAdded, '2026-04-29');

      final added = terms.firstWhere((t) => t.source == '白鳥沙羅');
      expect(added.createdBy, 'user');
      expect(added.kind, 'proper_noun');
      expect(added.dateAdded, GlossaryService.todayStamp());
    });

    test('bỏ qua mục rỗng và giữ định dạng file của tool Python', () async {
      await service.upsertAll(TranslationMode.japanese, {
        '  ': 'bỏ qua',
        '白鳥沙羅': '   ',
        '箸尾拓海': 'Hashio Takumi',
      });

      final terms = await service.readAll(TranslationMode.japanese);
      expect(terms.map((t) => t.source), ['菜畑小鳥', '箸尾拓海']);

      final bytes = await service
          .fileFor(TranslationMode.japanese)
          .readAsBytes();
      expect(bytes.first, '{'.codeUnitAt(0));
      expect(bytes.last, '}'.codeUnitAt(0));
      expect(RegExp(r'(?<!\r)\n').hasMatch(utf8.decode(bytes)), isFalse);
    });

    test('upsertAll rỗng không đụng vào file', () async {
      final before = await service.fileFor(TranslationMode.japanese).readAsString();
      await service.upsertAll(TranslationMode.japanese, {});
      final after = await service.fileFor(TranslationMode.japanese).readAsString();
      expect(after, before);
    });
  });
}
