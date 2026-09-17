import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/data/user_dict_service.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/dictionary_search/domain/dictionary_search.dart';
import 'package:vietyaku/features/dictionary_sync/application/dictionary_sync_controller.dart';
import 'package:vietyaku/features/dictionary_sync/data/dictionary_sync_api.dart';
import 'package:vietyaku/features/dictionary_sync/domain/shared_dictionary_entry.dart';
import 'package:vietyaku/features/glossary/data/glossary_service.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/translation_controller.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/domain/vietphrase_value.dart';
import 'package:vietyaku/shared/widgets/entry_edit_dialog.dart';

const _sampleGlossary = '''{
  "name": "Global Glossary",
  "lang": "JP",
  "is_shared": true,
  "is_published": false,
  "public_id": "",
  "terms": [
    {
      "source": "菜畑小鳥",
      "target": "Nabata Kotori",
      "kind": "proper_noun",
      "notes": "",
      "created_by": "A.I",
      "date_added": "2026-04-29"
    }
  ]
}''';

class MockDictionariesNotifier extends DictionariesNotifier {
  final LoadedDictionaries data;
  MockDictionariesNotifier(this.data);

  @override
  Future<LoadedDictionaries> build() async => data;

  @override
  Future<void> reload() async {}
}

class MockDictionarySyncController extends DictionarySyncController {
  SharedDictionaryEntry? lastStagedEntry;
  TranslationMode? lastStagedMode;

  @override
  DictionarySyncState build() => DictionarySyncState(
    session: AdminSession(username: 'admin', token: 'token'),
  );

  @override
  Future<void> stageLocalEdit({
    required TranslationMode mode,
    required SharedDictionaryKind kind,
    required String source,
    required String target,
  }) async {
    lastStagedMode = mode;
    lastStagedEntry = SharedDictionaryEntry(
      kind: kind,
      source: source,
      target: target,
    );
    state = state.copyWith(
      message:
          'Đã lưu ${kind == SharedDictionaryKind.vietPhrase ? 'VietPhrase' : 'Lạc Việt'}. Bấm Update để gửi lên server.',
    );
  }
}

LoadedDictionaries _createMock({
  Map<String, String>? userDictEntries,
  Map<String, String>? userNamesEntries,
  Map<String, String>? namesEntries,
  Map<String, String>? vietPhraseEntries,
  Map<String, String>? lacVietEntries,
  Map<String, String>? chinesePhienAmEntries,
  Map<String, String>? jaViEntries,
  Map<String, String>? maziiEntries,
  Map<String, String>? cedictEntries,
  Map<String, String>? sudachiReadingsEntries,
}) {
  final empty = PhraseDictionary(DictType.vietPhrase, const {});
  return LoadedDictionaries(
    userDict: userDictEntries == null
        ? empty
        : PhraseDictionary(DictType.userDict, userDictEntries),
    names: namesEntries == null
        ? (userNamesEntries == null
            ? empty
            : PhraseDictionary(DictType.names, userNamesEntries))
        : PhraseDictionary(DictType.names, {
            ...namesEntries,
            ...?userNamesEntries,
          }),
    vietPhrase: PhraseDictionary(
      DictType.vietPhrase,
      vietPhraseEntries ?? const {'菜畑小鳥': 'Nabata Kotori'},
    ),
    lacViet: lacVietEntries == null
        ? empty
        : PhraseDictionary(DictType.lacViet, lacVietEntries),
    mazii: maziiEntries == null
        ? null
        : PhraseDictionary(DictType.mazii, maziiEntries),
    chinesePhienAm: chinesePhienAmEntries == null
        ? empty
        : PhraseDictionary(DictType.chinesePhienAm, chinesePhienAmEntries),
    pronouns: empty,
    babylon: empty,
    thieuChuu: empty,
    cedict: cedictEntries == null
        ? empty
        : PhraseDictionary(DictType.cedict, cedictEntries),
    chinesePhienAmEnglish: empty,
    jaVi: jaViEntries == null
        ? empty
        : PhraseDictionary(DictType.jaVi, jaViEntries),
    zhVi: empty,
    sudachiReadings: sudachiReadingsEntries == null
        ? empty
        : PhraseDictionary(DictType.jaVi, sudachiReadingsEntries),
    searchLayers: [
      DictionarySearchLayer(
        id: 'userDict',
        label: 'UserDict',
        type: DictType.userDict,
        entries: userDictEntries ?? const {},
      ),
      DictionarySearchLayer(
        id: 'userNames',
        label: 'UserNames (overlay)',
        type: DictType.names,
        entries: userNamesEntries ?? const {},
      ),
      DictionarySearchLayer(
        id: 'names',
        label: 'Names gốc',
        type: DictType.names,
        entries: namesEntries ?? const {},
      ),
      DictionarySearchLayer(
        id: 'vietPhrase',
        label: 'VietPhrase',
        type: DictType.vietPhrase,
        entries: vietPhraseEntries ?? const {'菜畑小鳥': 'Nabata Kotori'},
      ),
    ],
    stats: const {},
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    GlossaryService.clearCache();
    tempDir = await Directory.systemTemp.createTemp('vietyaku_dialog_test');
    final jpDir = Directory(p.join(tempDir.path, 'JP'));
    await jpDir.create(recursive: true);
    await File(
      p.join(jpDir.path, GlossaryService.globalGlossaryFileName),
    ).writeAsString(_sampleGlossary, encoding: utf8);
  });

  tearDown(() async {
    GlossaryService.clearCache();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('GlossaryService find hoạt động với tempDir', () async {
    final service = GlossaryService(tempDir.path);
    expect(service.hasGlossaryFor(TranslationMode.japanese), isTrue);
    final term = await service.find(TranslationMode.japanese, '菜畑小鳥');
    expect(term, isNotNull);
    expect(term!.target, 'Nabata Kotori');
  });

  testWidgets(
    'GlossaryStatusCard hiển thị đúng và ẩn nút Cập nhật Glossary khi nghĩa giống hệt',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);

      final mockData = _createMock(
        vietPhraseEntries: {'菜畑小鳥': 'Nabata Kotori'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);
      await container
          .read(settingsProvider.notifier)
          .setGlossaryDir(tempDir.path);

      await tester.runAsync(() async {
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '菜畑小鳥',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Sửa vào VietPhrase'), findsOneWidget);
      expect(find.text('Trạng thái Glossary JP'), findsOneWidget);

      expect(find.text('ĐÃ CÓ TRONG GLOSSARY'), findsOneWidget);
      expect(find.text('Nabata Kotori'), findsWidgets);

      expect(find.text('Cập nhật theo VietPhrase'), findsNothing);
      expect(find.text('Thêm vào Glossary JP'), findsNothing);

      // Tắt autoUpdate → hiện nút "Cập nhật theo VietPhrase" trong thẻ trạng thái
      final autoUpdateCheckbox = find.widgetWithText(
        InkWell,
        'Tự động cập nhật Glossary JP khi bấm "Lưu từ"',
      );
      await tester.tap(autoUpdateCheckbox);
      await tester.pumpAndSettle();

      expect(find.text('Cập nhật theo VietPhrase'), findsOneWidget);
    },
  );

  testWidgets(
    'Lưu từ khi không khác biệt gì so với trước đó không thực hiện lưu (như Hủy)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {'菜畑小鳥': 'Nabata Kotori'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '菜畑小鳥',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Bấm nút Lưu từ mà không sửa đổi bất kỳ thứ gì
      final saveBtn = find.text('Lưu từ');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Dialog đóng mà không tạo message staging
      expect(find.text('Sửa vào VietPhrase'), findsNothing);
      expect(container.read(dictionarySyncProvider).message, isNull);

      // Pump để flush timer hoãn dispose (500ms)
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog VietPhrase/Lạc Việt hiện âm Hán Việt của từ nguồn, đổi key thì đổi theo',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {'菜畑小鳥': 'Nabata Kotori'},
        chinesePhienAmEntries: {
          '菜': 'thái',
          '畑': 'điền',
          '小': 'tiểu',
          '鳥': 'điểu',
          '空': 'không',
        },
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '菜畑小鳥',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Hán Việt: '), findsOneWidget);
      expect(find.text('Thái Điền Tiểu Điểu'), findsOneWidget);

      // Đổi từ nguồn → âm Hán Việt cập nhật theo.
      await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '空');
      await tester.pumpAndSettle();
      expect(find.text('Không'), findsOneWidget);

      // Key thuần kana không tra được chữ Hán nào → ẩn dòng Hán Việt.
      await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), 'そら');
      await tester.pumpAndSettle();
      expect(find.text('Hán Việt: '), findsNothing);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('Dialog UserDict/Names cũng hiện âm Hán Việt của từ nguồn', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mockData = _createMock(
      chinesePhienAmEntries: {'菜': 'thái', '畑': 'điền'},
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(
          () => MockDictionariesNotifier(mockData),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentModeProvider.notifier).state =
        TranslationMode.japanese;
    await container.read(dictionariesProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showEntryEditDialog(
                    context,
                    WidgetRefContext(context, container),
                    word: '菜畑',
                    toNames: false,
                  ),
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Sửa nghĩa trong UserDict'), findsOneWidget);
    expect(find.text('Hán Việt: '), findsOneWidget);
    expect(find.text('Thái Điền'), findsOneWidget);

    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'Dialog Lạc Việt: ô Nghĩa hiện \\n\\t đã unescape, lưu thì escape lại + / → "; "',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        lacVietEntries: {'拠る': r'\t- phí tổn\n\t- nhờ vào'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '拠る',
                      kind: SharedDictionaryKind.lacViet,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Sửa vào Lạc Việt'), findsOneWidget);
      // Ô Nghĩa hiển thị xuống dòng/tab thật, không phải literal \n\t.
      expect(find.text('\t- phí tổn\n\t- nhờ vào'), findsOneWidget);
      // Preview vẫn là value đúng như sẽ ghi vào file (escape).
      expect(find.text(r'\t- phí tổn\n\t- nhờ vào'), findsOneWidget);

      final meaningField = find.widgetWithText(TextField, 'Nghĩa');
      await tester.enterText(
        meaningField,
        '\t- chiếm cứ/chiếm lấy/chiếm đóng\n\t- chiếm giữ',
      );
      await tester.pumpAndSettle();

      // "Giá trị mới" = đúng chuỗi sẽ được lưu.
      expect(
        find.text(r'\t- chiếm cứ; chiếm lấy; chiếm đóng\n\t- chiếm giữ'),
        findsOneWidget,
      );

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('Tự động cập nhật Glossary khi lưu từ nếu checkbox được chọn', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('glossary.dir', tempDir.path);

    final mockData = _createMock(vietPhraseEntries: {'菜畑小鳥': 'Nabata Kotori'});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(
          () => MockDictionariesNotifier(mockData),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentModeProvider.notifier).state =
        TranslationMode.japanese;
    await container.read(dictionariesProvider.future);
    await container
        .read(settingsProvider.notifier)
        .setGlossaryDir(tempDir.path);

    await tester.runAsync(() async {
      await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showSharedEntryEditDialog(
                    context,
                    WidgetRefContext(context, container),
                    word: '菜畑小鳥',
                    kind: SharedDictionaryKind.vietPhrase,
                  ),
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Checkbox tự động cập nhật Glossary hiển thị
    expect(
      find.text('Tự động cập nhật Glossary JP khi bấm "Lưu từ"'),
      findsOneWidget,
    );

    // Sửa ô Nghĩa
    final meaningField = find.widgetWithText(TextField, 'Nghĩa');
    await tester.enterText(meaningField, 'Kotori Mới');
    await tester.pumpAndSettle();

    // Bấm Lưu từ
    final saveBtn = find.text('Lưu từ');
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Kiểm tra Glossary đã tự động được cập nhật target mới
    await tester.runAsync(() async {
      final updatedTerm = await GlossaryService(
        tempDir.path,
      ).find(TranslationMode.japanese, '菜畑小鳥');
      expect(updatedTerm, isNotNull);
      expect(updatedTerm!.target, 'Kotori Mới');
    });

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'Thêm vào Glossary xong thì dialog Sửa vào VietPhrase tự cập nhật trạng thái',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);

      // 空 chưa có trong glossary mẫu (chỉ có 菜畑小鳥).
      final mockData = _createMock(vietPhraseEntries: {'空': 'Không'});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);
      await container
          .read(settingsProvider.notifier)
          .setGlossaryDir(tempDir.path);

      await tester.runAsync(() async {
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '空',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('CHƯA CÓ TRONG GLOSSARY'), findsOneWidget);
      expect(find.text('Thêm vào Glossary JP'), findsOneWidget);

      await tester.tap(find.text('Thêm vào Glossary JP'));
      await tester.pumpAndSettle();
      expect(find.text('Cập nhật Global Glossary JP'), findsOneWidget);

      await tester.tap(find.text('Thêm vào glossary'));
      // pumpAndSettle: chờ dialog xác nhận đóng hẳn — future của route chỉ
      // hoàn tất sau animation, code mới chạy tiếp tới lệnh ghi file.
      // Vòng runAsync/pump xen kẽ: ghi file glossary là I/O thật, chỉ hoàn tất
      // trên event loop thật, còn phần chạy tiếp sau `await` thì cần pump.
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Dialog cha đọc lại glossary: thẻ trạng thái đổi, nút Thêm tự ẩn vì
      // nghĩa trong glossary giờ đã giống hệt ô Nghĩa.
      expect(find.text('ĐÃ CÓ TRONG GLOSSARY'), findsOneWidget);
      expect(find.text('Thêm vào Glossary JP'), findsNothing);
      expect(find.text('Ghi đè Glossary JP'), findsNothing);

      await tester.runAsync(() async {
        final term = await GlossaryService(
          tempDir.path,
        ).find(TranslationMode.japanese, '空');
        expect(term, isNotNull);
        expect(term!.target, 'Không');
      });

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog VietPhrase tách nghĩa cũ, chọn từ loại và thêm nghĩa tiếp theo',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {
          '楽しみ': '(n)vui vẻ/khoái lạc/(2)/(v)/thưởng thức/(3)háo hức',
        },
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSharedEntryEditDialog(
                    context,
                    WidgetRefContext(context, container),
                    word: '楽しみ',
                    kind: SharedDictionaryKind.vietPhrase,
                  ),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      TextField meaningField(int id) => tester.widget<TextField>(
        find.byKey(ValueKey('vietphrase-meaning-$id')),
      );
      DropdownButtonFormField<VietPhrasePartOfSpeech> partField(int id) =>
          tester.widget<DropdownButtonFormField<VietPhrasePartOfSpeech>>(
            find.byKey(ValueKey('vietphrase-pos-$id')),
          );

      expect(meaningField(0).controller!.text, 'vui vẻ/khoái lạc');
      expect(meaningField(1).controller!.text, 'thưởng thức');
      expect(meaningField(2).controller!.text, 'háo hức');
      expect(partField(0).initialValue, VietPhrasePartOfSpeech.noun);
      expect(partField(1).initialValue, VietPhrasePartOfSpeech.verb);
      expect(partField(2).initialValue, VietPhrasePartOfSpeech.none);
      expect(
        find.textContaining('Dùng dấu / cho các cách dịch trong cùng một tầng'),
        findsOneWidget,
      );

      final addButton = find.byKey(const ValueKey('add-vietphrase-meaning'));
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vietphrase-meaning-3')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('vietphrase-meaning-3')),
        'mong đợi',
      );
      await tester.tap(find.byKey(const ValueKey('vietphrase-pos-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tính từ (adj)').last);
      await tester.pumpAndSettle();

      expect(partField(3).initialValue, VietPhrasePartOfSpeech.adjective);

      final cancel = find.text('Hủy');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Đổi Từ nguồn thì ô Nghĩa nạp lại nghĩa của key mới (VietPhrase)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {'水晶宫': 'thủy tinh cung', '水晶': 'thủy tinh'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.chinese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '水晶宫',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      String meaningText() => tester
          .widget<TextField>(find.widgetWithText(TextField, 'Nghĩa'))
          .controller!
          .text;

      expect(meaningText(), 'thủy tinh cung');

      // Xóa bớt ký tự cuối → nghĩa của cụm ngắn hơn phải hiện ra.
      await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '水晶');
      await tester.pumpAndSettle();
      expect(meaningText(), 'thủy tinh');

      // Key không có trong từ điển → ô Nghĩa trống, không giữ nghĩa cũ.
      await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '宫');
      await tester.pumpAndSettle();
      expect(meaningText(), '');

      final cancel = find.text('Hủy');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('Đổi Từ nguồn không đè lên ô Nghĩa mà người dùng đã tự sửa', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mockData = _createMock(
      vietPhraseEntries: {'水晶宫': 'thủy tinh cung', '水晶': 'thủy tinh'},
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(
          () => MockDictionariesNotifier(mockData),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentModeProvider.notifier).state =
        TranslationMode.chinese;
    await container.read(dictionariesProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showSharedEntryEditDialog(
                    context,
                    WidgetRefContext(context, container),
                    word: '水晶宫',
                    kind: SharedDictionaryKind.vietPhrase,
                  ),
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nghĩa'),
      'nghĩa tự soạn',
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '水晶');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Nghĩa'))
          .controller!
          .text,
      'nghĩa tự soạn',
    );

    final cancel = find.text('Hủy');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('Đổi Từ nguồn nạp lại ô Nghĩa của dialog Lạc Việt', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mockData = _createMock(
      vietPhraseEntries: const {},
      lacVietEntries: {'水晶宫': 'thủy tinh cung', '水晶': 'thủy tinh'},
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(
          () => MockDictionariesNotifier(mockData),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentModeProvider.notifier).state =
        TranslationMode.chinese;
    await container.read(dictionariesProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showSharedEntryEditDialog(
                    context,
                    WidgetRefContext(context, container),
                    word: '水晶宫',
                    kind: SharedDictionaryKind.lacViet,
                  ),
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    String meaningText() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Nghĩa'))
        .controller!
        .text;

    expect(meaningText(), 'thủy tinh cung');

    await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '水晶');
    await tester.pumpAndSettle();
    expect(meaningText(), 'thủy tinh');

    final cancel = find.text('Hủy');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('Nút Xóa từ bám theo Từ nguồn hiện tại, không phải từ lúc mở', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mockData = _createMock(
      vietPhraseEntries: {'水晶宫': 'thủy tinh cung', '水晶': 'thủy tinh'},
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(
          () => MockDictionariesNotifier(mockData),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentModeProvider.notifier).state =
        TranslationMode.chinese;
    await container.read(dictionariesProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showSharedEntryEditDialog(
                    context,
                    WidgetRefContext(context, container),
                    word: '水晶宫',
                    kind: SharedDictionaryKind.vietPhrase,
                  ),
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Xóa từ'), findsOneWidget);

    // Key mới chưa có trong từ điển → không còn gì để xóa.
    await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '宫');
    await tester.pumpAndSettle();
    expect(find.text('Xóa từ'), findsNothing);

    // Quay lại một key có thật → nút hiện lại.
    await tester.enterText(find.widgetWithText(TextField, 'Từ nguồn'), '水晶');
    await tester.pumpAndSettle();
    expect(find.text('Xóa từ'), findsOneWidget);

    final cancel = find.text('Hủy');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'Khi tắt Tự động cập nhật Glossary, hiện nút Cập nhật theo VietPhrase trước nút Sửa nghĩa Glossary với 2 màu khác nhau',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);

      final mockData = _createMock(
        vietPhraseEntries: {'菜畑小鳥': 'Nabata Kotori'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);
      await container
          .read(settingsProvider.notifier)
          .setGlossaryDir(tempDir.path);

      await tester.runAsync(() async {
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '菜畑小鳥',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Mặc định autoUpdate bật → chưa hiện 2 nút này
      expect(find.text('Cập nhật theo VietPhrase'), findsNothing);
      expect(find.text('Sửa nghĩa Glossary JP'), findsNothing);

      // Tắt checkbox "Tự động cập nhật Glossary JP khi bấm 'Lưu từ'"
      final autoUpdateCheckbox = find.widgetWithText(
        InkWell,
        'Tự động cập nhật Glossary JP khi bấm "Lưu từ"',
      );
      expect(autoUpdateCheckbox, findsOneWidget);
      await tester.tap(autoUpdateCheckbox);
      await tester.pumpAndSettle();

      // Sau khi tắt autoUpdate, cả 2 nút đều xuất hiện
      final vpBtnFinder = find.widgetWithText(
        TextButton,
        'Cập nhật theo VietPhrase',
      );
      final editBtnFinder = find.widgetWithText(
        TextButton,
        'Sửa nghĩa Glossary JP',
      );
      expect(vpBtnFinder, findsOneWidget);
      expect(editBtnFinder, findsOneWidget);

      // Nút "Cập nhật theo VietPhrase" nằm trước nút "Sửa nghĩa Glossary JP" trong Wrap
      final vpOffset = tester.getTopLeft(vpBtnFinder);
      final editOffset = tester.getTopLeft(editBtnFinder);
      if (vpOffset.dy == editOffset.dy) {
        expect(vpOffset.dx, lessThan(editOffset.dx));
      } else {
        expect(vpOffset.dy, lessThan(editOffset.dy));
      }

      // 2 nút có màu sắc khác nhau rõ rệt
      final vpBtn = tester.widget<TextButton>(vpBtnFinder);
      final editBtn = tester.widget<TextButton>(editBtnFinder);
      final vpFg = vpBtn.style?.foregroundColor?.resolve({});
      final editFg = editBtn.style?.foregroundColor?.resolve({});
      expect(vpFg, isNotNull);
      expect(editFg, isNotNull);
      expect(vpFg, isNot(equals(editFg)));
      expect(vpFg, const Color(0xFF00838F));
      expect(editFg, const Color(0xFF6A1B9A));

      final cancel = find.text('Hủy');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Khi từ chưa có trong Glossary, nút Thêm vào Glossary nằm trong thẻ trạng thái Glossary',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);

      final mockData = _createMock(vietPhraseEntries: {'空': 'Không'});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);
      await container
          .read(settingsProvider.notifier)
          .setGlossaryDir(tempDir.path);

      await tester.runAsync(() async {
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '空',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('CHƯA CÓ TRONG GLOSSARY'), findsOneWidget);

      final addBtnFinder = find.widgetWithText(
        TextButton,
        'Thêm vào Glossary JP',
      );
      expect(addBtnFinder, findsOneWidget);

      // Nút "Thêm vào Glossary JP" nằm trong thẻ trạng thái (ở phía trên hàng action "Hủy" / "Lưu từ")
      final addBtnTop = tester.getTopLeft(addBtnFinder).dy;
      final cancelTop = tester.getTopLeft(find.text('Hủy')).dy;
      expect(addBtnTop, lessThan(cancelTop));

      // Hàng actions ở đáy chỉ có Hủy, Lưu từ (và Xóa từ nếu có), không còn nút Glossary
      final actionsRow = find.ancestor(
        of: find.text('Hủy'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: actionsRow, matching: find.text('Thêm vào Glossary JP')),
        findsNothing,
      );

      final cancel = find.text('Hủy');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog Thêm vào Names: hiện nút Xóa từ khi từ đã có trong UserNames, ẩn khi chưa có',
    (tester) async {
      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);
      await tester.runAsync(() async {
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });
      final mockData = _createMock(
        userNamesEntries: {'佐助': 'Sasuke'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '佐助',
                      toNames: true,
                    ),
                    child: const Text('Open Names Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Names Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Thêm vào Names'), findsOneWidget);
      expect(find.text('Xóa từ'), findsOneWidget);

      // Đổi Từ nguồn sang từ chưa có trong UserNames -> nút Xóa từ biến mất
      final keyField = find.widgetWithText(TextField, 'Từ nguồn');
      await tester.enterText(keyField, '鳴人');
      await tester.pumpAndSettle();

      expect(find.text('Xóa từ'), findsNothing);

      // Đổi lại '佐助' -> nút Xóa từ xuất hiện lại
      await tester.enterText(keyField, '佐助');
      await tester.pumpAndSettle();

      expect(find.text('Xóa từ'), findsOneWidget);

      final cancel = find.text('Hủy');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog Thêm vào Names: bấm Xóa từ mở dialog xác nhận và xóa khỏi UserNames.txt',
    (tester) async {
      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);

      final service = UserDictService(AppPaths(tempDir));
      await tester.runAsync(() async {
        await service.upsertUserName('佐助', 'Sasuke');
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      final mockData = _createMock(
        userNamesEntries: {'佐助': 'Sasuke'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) async => AppPaths(tempDir)),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(appPathsProvider.future);
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '佐助',
                      toNames: true,
                    ),
                    child: const Text('Open Names Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Names Dialog'));
      await tester.pumpAndSettle();

      final deleteBtn = find.text('Xóa từ');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      // Dialog xác nhận xóa xuất hiện
      expect(find.text('Xác nhận xóa từ "佐助"'), findsOneWidget);
      expect(find.text('Xóa khỏi Names trên máy này.'), findsOneWidget);

      // Bấm Xác nhận xóa
      final confirmBtn = find.text('Xác nhận xóa');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Kiểm tra file UserNames.txt đã bị xóa key
      await tester.runAsync(() async {
        final content = await service.userNamesFile.readAsString();
        expect(content.contains('佐助='), isFalse);
      });

      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog Thêm vào Names: từ chỉ có trong Glossary không hiện nút Xóa từ; có cả hai thì xóa chỉ xóa UserNames và giữ nguyên Glossary',
    (tester) async {
      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glossary.dir', tempDir.path);

      final glossaryService = GlossaryService(tempDir.path);
      final service = UserDictService(AppPaths(tempDir));
      await tester.runAsync(() async {
        await service.upsertUserName('佐助', 'Sasuke');
        await glossaryService.upsert(
          TranslationMode.japanese,
          source: '佐助',
          target: 'Sasuke (Glossary)',
        );
        await glossaryService.upsert(
          TranslationMode.japanese,
          source: '鳴人',
          target: 'Naruto (Glossary)',
        );
      });

      final mockData = _createMock(
        userNamesEntries: {'佐助': 'Sasuke'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) async => AppPaths(tempDir)),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(appPathsProvider.future);
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '鳴人',
                      toNames: true,
                    ),
                    child: const Text('Open Names Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Mở với '鳴人' (chỉ có trong Glossary, KHÔNG có trong UserNames)
      await tester.tap(find.text('Open Names Dialog'));
      await tester.pumpAndSettle();

      // Nút Xóa từ KHÔNG được xuất hiện
      expect(find.text('Xóa từ'), findsNothing);

      // Đổi sang '佐助' (có trong cả UserNames và Glossary)
      final keyField = find.widgetWithText(TextField, 'Từ nguồn');
      await tester.enterText(keyField, '佐助');
      await tester.pumpAndSettle();

      // Nút Xóa từ xuất hiện vì có trong UserNames
      expect(find.text('Xóa từ'), findsOneWidget);

      await tester.tap(find.text('Xóa từ'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      // Dialog xác nhận xóa xuất hiện, chỉ có lựa chọn xóa Names, KHÔNG có lựa chọn xóa Glossary
      expect(find.text('Xác nhận xóa từ "佐助"'), findsOneWidget);
      expect(find.text('Xóa khỏi Names trên máy này.'), findsOneWidget);
      expect(find.textContaining('Glossary'), findsNothing);

      // Bấm Xác nhận xóa
      final confirmBtn = find.text('Xác nhận xóa');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Kiểm tra file UserNames.txt đã bị xóa key, nhưng Glossary VẪN CÒN NGUYÊN '佐助'
      await tester.runAsync(() async {
        final content = await service.userNamesFile.readAsString();
        expect(content.contains('佐助='), isFalse);

        final glossaryTerm = await glossaryService.find(
          TranslationMode.japanese,
          '佐助',
        );
        expect(glossaryTerm, isNotNull);
        expect(glossaryTerm!.target, 'Sasuke (Glossary)');
      });

      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog Lạc Việt: từ chưa có trong Lạc Việt (dù có trong VietPhrase) -> không hiện nút Xóa từ',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {'水晶宫': 'thủy tinh cung'},
        lacVietEntries: {'学校': 'trường học'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.chinese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '水晶宫',
                      kind: SharedDictionaryKind.lacViet,
                    ),
                    child: const Text('Open LacViet Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open LacViet Dialog'));
      await tester.pumpAndSettle();

      // '水晶宫' có trong VietPhrase nhưng KHÔNG có trong Lạc Việt -> KHÔNG có nút Xóa từ
      expect(find.text('Xóa từ'), findsNothing);

      // Đổi sang '学校' (có trong Lạc Việt) -> nút Xóa từ xuất hiện
      final keyField = find.widgetWithText(TextField, 'Từ nguồn');
      await tester.enterText(keyField, '学校');
      await tester.pumpAndSettle();
      expect(find.text('Xóa từ'), findsOneWidget);

      // Đổi lại '水晶宫' -> nút Xóa từ biến mất
      await tester.enterText(keyField, '水晶宫');
      await tester.pumpAndSettle();
      expect(find.text('Xóa từ'), findsNothing);

      final cancel = find.text('Hủy');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog VietPhrase tiếng Trung: hiện Hán Việt và Phát âm bên phải, đổi key thì cập nhật theo',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {'重大': 'trọng đại'},
        chinesePhienAmEntries: {'重': 'trọng', '大': 'đại'},
        lacVietEntries: {
          '重大': '[zhòngdà]\\n\\t trọng đại',
          '重': '[chóng]\\n\\t trùng',
          '大': '[dà]\\n\\t to lớn',
          '美': '[měi]',
          '丽': '[lì]',
        },
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.chinese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '重大',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Cả Hán Việt và Phát âm cùng hiển thị (phát âm có cả phrase và ghép khác nhau)
      expect(find.text('Hán Việt: '), findsOneWidget);
      expect(find.text('Trọng Đại'), findsOneWidget);
      expect(find.text('Phát âm: '), findsOneWidget);
      expect(find.text('zhòngdà (ghép: chóng dà)'), findsOneWidget);

      // Đổi sang '美丽' (chỉ có phát âm ghép từ từng chữ)
      final keyField = find.widgetWithText(TextField, 'Từ nguồn');
      await tester.enterText(keyField, '美丽');
      await tester.pumpAndSettle();
      expect(find.text('Phát âm: '), findsOneWidget);
      expect(find.text('měi lì'), findsOneWidget);

      // Đổi sang chuỗi > 10 chữ -> bỏ qua ghép từng chữ, không có phát âm -> ẩn
      await tester.enterText(keyField, '一二三四五六七八九十一');
      await tester.pumpAndSettle();
      expect(find.text('Phát âm: '), findsNothing);

      final cancel = find.text('Hủy');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog VietPhrase tiếng Nhật: hiện Hán Việt và Phát âm bên phải (Sudachi / thuần kana)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockData = _createMock(
        vietPhraseEntries: {'学校': 'trường học'},
        chinesePhienAmEntries: {'学': 'học', '校': 'hiệu'},
        sudachiReadingsEntries: {'学校': 'がっこう'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '学校',
                      kind: SharedDictionaryKind.vietPhrase,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Hiện cả Hán Việt và Phát âm Sudachi
      expect(find.text('Hán Việt: '), findsOneWidget);
      expect(find.text('Học Hiệu'), findsOneWidget);
      expect(find.text('Phát âm: '), findsOneWidget);
      expect(find.text('がっこう'), findsOneWidget);

      // Đổi sang thuần kana 'ありがとう' -> ẩn Hán Việt, phát âm hiện chính chuỗi kana
      final keyField = find.widgetWithText(TextField, 'Từ nguồn');
      await tester.enterText(keyField, 'ありがとう');
      await tester.pumpAndSettle();
      expect(find.text('Hán Việt: '), findsNothing);
      expect(find.text('Phát âm: '), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'ありがとう'), findsOneWidget);

      final cancel = find.text('Hủy');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog Lạc Việt: từ chưa có trong Lạc Việt nhưng có trong VietPhrase -> tiêu đề "Thêm vào Lạc Việt", nút "Thêm từ", bấm "Thêm từ" thì lưu vào từ điển',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'dictionarySync.admin.username': 'admin',
        'dictionarySync.admin.token': 'jwt-token',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockPaths = AppPaths(tempDir);
      final mockData = _createMock(
        vietPhraseEntries: {'再入荷': 'tái nhập hàng'},
        lacVietEntries: const {},
      );
      final mockSyncController = MockDictionarySyncController();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) async => mockPaths),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
          dictionarySyncProvider.overrideWith(() => mockSyncController),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '再入荷',
                      kind: SharedDictionaryKind.lacViet,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tiêu đề hiển thị "Thêm vào Lạc Việt"
      expect(find.text('Thêm vào Lạc Việt'), findsOneWidget);
      expect(find.text('Sửa vào Lạc Việt'), findsNothing);

      // Nghĩa tự động lấy từ VietPhrase qua: 'tái nhập hàng'
      expect(find.widgetWithText(TextField, 'tái nhập hàng'), findsOneWidget);

      // Nút là "Thêm từ"
      final addBtn = find.text('Thêm từ');
      expect(addBtn, findsOneWidget);
      expect(find.text('Lưu từ'), findsNothing);

      // Bấm nút "Thêm từ" mà không cần sửa đổi gì
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Phải thực hiện lưu và cập nhật từ điển (gọi stageLocalEdit với đúng thông tin)
      expect(mockSyncController.lastStagedEntry, isNotNull);
      expect(mockSyncController.lastStagedEntry?.source, '再入荷');
      expect(mockSyncController.lastStagedEntry?.target, 'tái nhập hàng');
      expect(
        mockSyncController.lastStagedEntry?.kind,
        SharedDictionaryKind.lacViet,
      );
      expect(mockSyncController.lastStagedMode, TranslationMode.japanese);

      final syncState = container.read(dictionarySyncProvider);
      expect(syncState.message, contains('Đã lưu Lạc Việt'));

      await tester.pump(const Duration(milliseconds: 600));

      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog Lạc Việt: đổi Từ nguồn sang từ đã có trong Lạc Việt thì nút tự đổi thành "Lưu từ", đổi lại từ chưa có thì thành "Thêm từ"',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'dictionarySync.admin.username': 'admin',
        'dictionarySync.admin.token': 'jwt-token',
      });
      final prefs = await SharedPreferences.getInstance();
      final mockPaths = AppPaths(tempDir);
      final mockData = _createMock(
        vietPhraseEntries: {'再入荷': 'tái nhập hàng'},
        lacVietEntries: {'学校': 'trường học'},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) async => mockPaths),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showSharedEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '再入荷',
                      kind: SharedDictionaryKind.lacViet,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Ban đầu: '再入荷' chưa có trong Lạc Việt -> nút 'Thêm từ'
      expect(find.text('Thêm từ'), findsOneWidget);
      expect(find.text('Lưu từ'), findsNothing);

      // Đổi sang '学校' (đã có trong Lạc Việt) -> nút đổi thành 'Lưu từ'
      final keyField = find.widgetWithText(TextField, 'Từ nguồn');
      await tester.enterText(keyField, '学校');
      await tester.pumpAndSettle();
      expect(find.text('Lưu từ'), findsOneWidget);
      expect(find.text('Thêm từ'), findsNothing);

      // Đổi lại '再入荷' (chưa có trong Lạc Việt) -> nút đổi lại thành 'Thêm từ'
      await tester.enterText(keyField, '再入荷');
      await tester.pumpAndSettle();
      expect(find.text('Thêm từ'), findsOneWidget);
      expect(find.text('Lưu từ'), findsNothing);

      final cancel = find.text('Hủy');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Dialog UserDict: từ chưa có trong UserDict nhưng có trong VietPhrase -> tiêu đề "Thêm vào UserDict", nút "Thêm từ", bấm "Thêm từ" thì lưu vào UserDict',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final mockPaths = AppPaths(tempDir);
      final mockData = _createMock(
        vietPhraseEntries: {'再入荷': 'tái nhập hàng'},
        userDictEntries: const {},
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) async => mockPaths),
          dictionariesProvider.overrideWith(
            () => MockDictionariesNotifier(mockData),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container.read(dictionariesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showEntryEditDialog(
                      context,
                      WidgetRefContext(context, container),
                      word: '再入荷',
                      toNames: false,
                      title: 'Thêm vào UserDict',
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tiêu đề hiển thị "Thêm vào UserDict"
      expect(find.text('Thêm vào UserDict'), findsOneWidget);
      expect(find.text('Sửa vào UserDict'), findsNothing);

      // Nút là "Thêm từ"
      final addBtn = find.text('Thêm từ');
      expect(addBtn, findsOneWidget);
      expect(find.text('Lưu từ'), findsNothing);

      // Bấm nút "Thêm từ" mà không cần sửa đổi gì
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // File UserDict.txt phải được ghi với từ mới
      final userDictFile = File(
        p.join(tempDir.path, 'dictionaries', 'UserDict.txt'),
      );
      await tester.runAsync(() async {
        expect(await userDictFile.exists(), isTrue);
        final content = await userDictFile.readAsString();
        expect(content, contains('再入荷=tái nhập hàng'));
      });

      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}

class WidgetRefContext implements WidgetRef {
  WidgetRefContext(this.context, this.container);
  @override
  final BuildContext context;
  final ProviderContainer container;

  @override
  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  T watch<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {}

  @override
  bool exists(ProviderBase<dynamic> provider) => container.exists(provider);

  @override
  void invalidate(ProviderOrFamily provider) => container.invalidate(provider);

  @override
  ProviderSubscription<T> listenManual<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = false,
  }) {
    return container.listen(
      provider,
      listener,
      fireImmediately: fireImmediately,
    );
  }

  ProviderSubscription<T> listenSelf<T>(
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    throw UnimplementedError();
  }

  @override
  T refresh<T>(Refreshable<T> provider) => container.refresh(provider);
}
