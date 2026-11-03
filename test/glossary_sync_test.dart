import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/clipboard/application/clipboard_reader_controller.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/data/user_dict_service.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/glossary/application/glossary_sync_controller.dart';
import 'package:vietyaku/features/glossary/data/glossary_service.dart';
import 'package:vietyaku/features/glossary/presentation/glossary_sync_screen.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/domain/vietphrase_value.dart';

class _FakeDictionariesNotifier extends DictionariesNotifier {
  _FakeDictionariesNotifier(this.dicts);
  final LoadedDictionaries dicts;
  int reloadCalls = 0;

  @override
  Future<LoadedDictionaries> build() async => dicts;

  @override
  Future<void> reload() async {
    reloadCalls++;
  }
}

LoadedDictionaries _fakeLoadedDictionaries(Map<String, String> vietPhraseMap) {
  final empty = PhraseDictionary(DictType.userDict, const {});
  return LoadedDictionaries(
    userDict: empty,
    names: empty,
    vietPhrase: PhraseDictionary(DictType.vietPhrase, vietPhraseMap),
    lacViet: empty,
    chinesePhienAm: empty,
    pronouns: empty,
    babylon: empty,
    thieuChuu: empty,
    cedict: empty,
    chinesePhienAmEnglish: empty,
    jaVi: empty,
    zhVi: empty,
    stats: const {},
  );
}

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

    test('removeAll ghi từ đã xóa vào blocked_sources để ATB không lưu lại từ AI, và upsertAll gỡ chặn', () async {
      await service.removeAll(TranslationMode.japanese, ['菜畑小鳥', '白鳥沙羅']);
      expect(await service.readAll(TranslationMode.japanese), isEmpty);
      expect(
        await service.readBlockedSources(TranslationMode.japanese),
        ['菜畑小鳥', '白鳥沙羅'],
      );

      // Khi người dùng chủ động thêm lại một từ thì gỡ từ đó khỏi blocked_sources
      await service.upsertAll(TranslationMode.japanese, {'菜畑小鳥': 'Nabata Kotori'});
      expect(
        await service.readBlockedSources(TranslationMode.japanese),
        ['白鳥沙羅'],
      );
    });
  });

  group('allVietPhraseMeaningsClean fast-path & complex', () {
    test('trả nguyên chuỗi đã sạch (fast-path) và chuẩn hóa chuỗi có marker', () {
      const cleanSingle = 'ký ức';
      const cleanMulti = 'ký ức/hồi ức/nhớ lại';
      expect(identical(allVietPhraseMeaningsClean(cleanSingle), cleanSingle), isTrue);
      expect(identical(allVietPhraseMeaningsClean(cleanMulti), cleanMulti), isTrue);

      expect(
        allVietPhraseMeaningsClean('(n)/ký ức/hồi ức/(2)/(v)/nhớ lại'),
        'ký ức/hồi ức/nhớ lại',
      );
      expect(
        allVietPhraseMeaningsClean('  ký ức / hồi ức // nhớ lại '),
        'ký ức/hồi ức/nhớ lại',
      );
      expect(allVietPhraseMeaningsClean('   '), '');
    });
  });

  group('UserDictService.removeGeneratedEntries', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('vietyaku_bulk_remove');
    });

    tearDown(() async => root.delete(recursive: true));

    test('xóa hàng loạt nhiều key trong một lượt ghi cho VietPhraseOverlay và AiEntries', () async {
      final service = UserDictService(AppPaths(root));
      await service.upsertVietPhraseOverlay(
        TranslationMode.japanese,
        {'A': '1', 'B': '2', 'C': '3'},
      );
      await service.upsertAiEntries(
        TranslationMode.japanese,
        {'B': 'hai', 'D': 'bốn'},
      );

      final removed = await service.removeGeneratedEntries(
        TranslationMode.japanese,
        ['A', 'B'],
      );
      expect(removed, isTrue);

      final overlayContent = await service
          .vietPhraseOverlayFile(TranslationMode.japanese)
          .readAsString();
      expect(overlayContent.trim(), contains('C=3'));
      expect(overlayContent.trim(), isNot(contains('A=1')));

      final aiEntriesContent = await service
          .aiEntriesFile(TranslationMode.japanese)
          .readAsString();
      expect(aiEntriesContent.trim(), contains('D=bốn'));
      expect(aiEntriesContent.trim(), isNot(contains('B=hai')));
    });
  });

  group('WindowsClipboardBridge multi-window channel', () {
    const channel = MethodChannel('vietyaku/windows_bridge');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('gửi openGlossarySyncWindow và notify giữa 2 cửa sổ', (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'openGlossarySyncWindow') return true;
            return true;
          });

      final bridge = WindowsClipboardBridge();
      final opened = await bridge.openGlossarySyncWindow(mode: 'japanese');
      await bridge.notifyGlossaryWindow({'type': 'vietPhraseChanged'});
      await bridge.notifyMainWindow({'type': 'glossaryWindowChanged'});
      await bridge.closeGlossarySyncWindow();

      if (Platform.isWindows) {
        expect(opened, isTrue);
        expect(
          calls.map((c) => c.method),
          [
            'openGlossarySyncWindow',
            'notifyGlossaryWindow',
            'notifyMainWindow',
            'closeGlossarySyncWindow',
          ],
        );
      }
    });
  });

  group('GlossarySyncScreen standalone & incremental sync index', () {
    late Directory tempRoot;
    late Directory glossaryRoot;

    setUp(() async {
      GlossaryService.clearCache();
      invalidateVietPhraseSyncIndex();
      tempRoot = await Directory.systemTemp.createTemp('vietyaku_sync_ui');
      glossaryRoot = Directory(p.join(tempRoot.path, 'glossary'));
      final jpDir = Directory(p.join(glossaryRoot.path, 'JP'));
      await jpDir.create(recursive: true);
      await File(
        p.join(jpDir.path, GlossaryService.globalGlossaryFileName),
      ).writeAsString(_glossary, encoding: utf8, flush: true);
    });

    tearDown(() async {
      GlossaryService.clearCache();
      invalidateVietPhraseSyncIndex();
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    testWidgets(
      'cửa sổ độc lập ẩn nút Back và cập nhật dòng tức thì mà không reload từ điển nặng',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({
          'glossary.dir': glossaryRoot.path,
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeNotifier = _FakeDictionariesNotifier(
          _fakeLoadedDictionaries({'学校': 'trường học'}),
        );

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appPathsProvider.overrideWith((ref) async => AppPaths(tempRoot)),
            dictionariesProvider.overrideWith(() => fakeNotifier),
          ],
        );
        addTearDown(container.dispose);

        await tester.runAsync(() async {
          await GlossaryService(glossaryRoot.path).readAll(TranslationMode.japanese);
        });

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: GlossarySyncScreen(isStandaloneWindow: true),
            ),
          ),
        );

        await tester.runAsync(() async {
          await container.read(
            glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase).future,
          );
        });
        await tester.pumpAndSettle();

        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.automaticallyImplyLeading, isFalse);
        expect(find.text('菜畑小鳥'), findsOneWidget);

        // Bấm Cập nhật trên dòng '菜畑小鳥'
        await tester.tap(find.text('Cập nhật'));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();

        // Không gọi reload() nặng trên DictionariesNotifier nhưng mục đã chuyển
        // sang Giống hệt nhờ chỉ mục VietPhrase cập nhật tại chỗ.
        expect(fakeNotifier.reloadCalls, 0);
        expect(find.text('菜畑小鳥'), findsNothing);
      },
    );
  });
}
