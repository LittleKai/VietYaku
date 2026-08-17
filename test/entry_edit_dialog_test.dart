import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/dictionary_sync/application/dictionary_sync_controller.dart';
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
}

LoadedDictionaries _createMock({
  Map<String, String>? vietPhraseEntries,
  Map<String, String>? lacVietEntries,
  Map<String, String>? chinesePhienAmEntries,
}) {
  final empty = PhraseDictionary(DictType.vietPhrase, const {});
  return LoadedDictionaries(
    userDict: empty,
    names: empty,
    vietPhrase: PhraseDictionary(
      DictType.vietPhrase,
      vietPhraseEntries ?? const {'菜畑小鳥': 'Nabata Kotori'},
    ),
    lacViet: lacVietEntries == null
        ? empty
        : PhraseDictionary(DictType.lacViet, lacVietEntries),
    chinesePhienAm: chinesePhienAmEntries == null
        ? empty
        : PhraseDictionary(DictType.chinesePhienAm, chinesePhienAmEntries),
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

      expect(find.text('Ghi đè Glossary JP'), findsNothing);
      expect(find.text('Thêm vào Glossary JP'), findsNothing);

      final meaningField = find.widgetWithText(TextField, 'Nghĩa');
      await tester.enterText(meaningField, 'Kotori mới');
      await tester.pumpAndSettle();

      expect(find.text('Ghi đè Glossary JP'), findsOneWidget);
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
