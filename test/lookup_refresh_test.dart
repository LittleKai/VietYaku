import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/ai_translation/application/ai_lookup_controller.dart';
import 'package:vietyaku/features/ai_translation/application/ai_settings_controller.dart';
import 'package:vietyaku/features/ai_translation/data/ai_api_client.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_api_key.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_service_config.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_service_type.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/data/user_dict_service.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/application/token_selection.dart';
import 'package:vietyaku/features/translation/application/translation_controller.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

class _TestAiSettingsNotifier extends AiSettingsController {
  _TestAiSettingsNotifier(this.initial);
  final AiSettings initial;

  @override
  Future<AiSettings> build() async => initial;
}

/// Bộ dict thay được giữa chừng, mô phỏng `reload()` sau khi tra AI/online ghi
/// thêm mục vào từ điển.
class _MutableDicts extends DictionariesNotifier {
  _MutableDicts(this.loaded, {this.onReload});
  LoadedDictionaries loaded;
  final Future<LoadedDictionaries> Function()? onReload;

  @override
  Future<LoadedDictionaries> build() async => loaded;

  @override
  Future<void> reload() async {
    if (onReload != null) {
      loaded = await onReload!();
    }
    state = AsyncData(loaded);
  }
}

LoadedDictionaries _dicts({
  Map<String, String> vietPhrase = const {},
  Map<String, String> aiDict = const {},
  Map<String, String> aiEntries = const {},
}) {
  PhraseDictionary d(DictType t, Map<String, String> e) => PhraseDictionary(t, e);
  return LoadedDictionaries(
    userDict: d(DictType.userDict, const {}),
    names: d(DictType.names, const {}),
    vietPhrase: d(DictType.vietPhrase, vietPhrase),
    lacViet: d(DictType.lacViet, const {}),
    chinesePhienAm: d(DictType.chinesePhienAm, const {}),
    pronouns: d(DictType.pronouns, const {}),
    babylon: d(DictType.babylon, const {}),
    thieuChuu: d(DictType.thieuChuu, const {}),
    cedict: d(DictType.cedict, const {}),
    chinesePhienAmEnglish: d(DictType.chinesePhienAmEnglish, const {}),
    jaVi: d(DictType.jaVi, const {}),
    zhVi: d(DictType.zhVi, const {}),
    aiDict: d(DictType.aiDict, aiDict),
    aiEntries: d(DictType.aiEntries, aiEntries),
    stats: const {},
  );
}

void main() {
  Future<(ProviderContainer, _MutableDicts)> setUpContainer(
    LoadedDictionaries initial,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = _MutableDicts(initial);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(dictionariesProvider.future);
    return (container, notifier);
  }

  test('refreshCurrent hiện mục vừa ghi vào VietPhrase/AiEntries/AiDict', () async {
    final (container, notifier) = await setUpContainer(_dicts());
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('背徳');
    expect(container.read(lookupControllerProvider)!.sections, isEmpty);

    // Tra AI xong: overlay VietPhrase + AiEntries + AiDict đều có thêm mục.
    notifier.loaded = _dicts(
      vietPhrase: const {'背徳': 'phản bội đạo đức'},
      aiDict: const {'背徳': '<<AI Dịch>>\n{"meaning":"phản bội đạo đức"}'},
      aiEntries: const {'背徳': 'phản bội đạo đức'},
    );
    await container.read(dictionariesProvider.notifier).reload();
    lookup.refreshCurrent();

    final labels = container
        .read(lookupControllerProvider)!
        .sections
        .map((s) => s.label)
        .toSet();
    expect(labels, containsAll(<String>['VietPhrase', 'AI Dịch', 'AI tách từ']));
  });

  test('refreshCurrent giữ mục chỉ có trong phiên (nghĩa máy dịch)', () async {
    final (container, notifier) = await setUpContainer(_dicts());
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('背徳');
    lookup.addOnlineSections('背徳', const [
      LookupSection('背徳', 'Google Việt', 'bội đức'),
    ]);

    notifier.loaded = _dicts(vietPhrase: const {'背徳': 'phản bội đạo đức'});
    await container.read(dictionariesProvider.notifier).reload();
    lookup.refreshCurrent();

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => s.label), contains('VietPhrase'));
    expect(
      sections.singleWhere((s) => s.label == 'Google Việt').body,
      equals('bội đức'),
      reason: 'nghĩa máy dịch không được lưu vào từ điển nên tra lại sẽ mất',
    );
  });

  test('refreshCurrent bỏ mục vừa bị xóa khỏi từ điển', () async {
    final (container, notifier) = await setUpContainer(
      _dicts(vietPhrase: const {'背徳': 'phản bội đạo đức'}),
    );
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('背徳');
    expect(
      container.read(lookupControllerProvider)!.sections.map((s) => s.label),
      contains('VietPhrase'),
    );

    // Xóa từ: mục cũ KHÔNG được ghép lại, nếu không ô Nghĩa vẫn hiện
    // nghĩa vừa bị gỡ khỏi từ điển.
    notifier.loaded = _dicts();
    await container.read(dictionariesProvider.notifier).reload();
    lookup.refreshCurrent();

    expect(container.read(lookupControllerProvider)!.sections, isEmpty);
  });

  test('refreshCurrent không làm gì khi ô Nghĩa đang trống', () async {
    final (container, _) = await setUpContainer(_dicts());
    container.read(lookupControllerProvider.notifier).refreshCurrent();
    expect(container.read(lookupControllerProvider), isNull);
  });

  test('Hiển thị AI Dịch (Cả câu) khi câu chứa từ tra đã có trong AiDict', () async {
    const fullSentence = '彼が言ったことは本当だった。';
    final (container, _) = await setUpContainer(
      _dicts(
        vietPhrase: const {'言った': 'đã nói'},
        aiDict: const {
          fullSentence:
              '<<AI Dịch>>\n{"meaning":"Những điều anh ấy nói là sự thật."}',
        },
      ),
    );
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('言った', rawEnclosingSentence: fullSentence);

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => s.label), containsAll(['VietPhrase', 'AI Dịch (Cả câu)']));

    final sentenceSection = sections.singleWhere((s) => s.label == 'AI Dịch (Cả câu)');
    expect(sentenceSection.word, equals(fullSentence));
    expect(sentenceSection.body, contains('Những điều anh ấy nói là sự thật.'));
  });

  test('enclosingSentenceAt trích xuất đúng câu và nhận diện từ điển AiDict', () {
    const text = 'こんにちは。彼が言ったことは本当だった。信じられない！';
    final dicts = _dicts(
      aiDict: const {
        '彼が言ったことは本当だった。':
            '<<AI Dịch>>\n{"meaning":"Những điều anh ấy nói là sự thật."}',
      },
    );

    // Vị trí "言った" (khoảng index 9-11)
    final sent = enclosingSentenceAt(text, 9, 11, dicts: dicts);
    expect(sent, equals('彼が言ったことは本当だった。'));
  });

  testWidgets(
    'executeAiLookup tự động lưu từ điển (loại bỏ nhãn từ loại ở đầu), reload, dịch lại và cập nhật panel Nghĩa',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('ai_lookup_refresh_');
      addTearDown(() {
        try {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final paths = AppPaths(tempDir);
      final service = UserDictService(paths);
      const word = '背徳';
      const sentence = 'これは背徳だ。';
      final prefs = await SharedPreferences.getInstance();

      Map<String, String> parseEntries(File f) {
        if (!f.existsSync()) return {};
        final out = <String, String>{};
        for (final line in f.readAsLinesSync()) {
          final eq = line.indexOf('=');
          if (eq > 0) {
            out[line.substring(0, eq)] = line.substring(eq + 1);
          }
        }
        return out;
      }

      LoadedDictionaries buildDicts() => _dicts(
        vietPhrase: parseEntries(
          service.vietPhraseOverlayFile(TranslationMode.japanese),
        ),
        aiDict: parseEntries(service.aiDictFile(TranslationMode.japanese)),
        aiEntries: parseEntries(
          service.aiEntriesFile(TranslationMode.japanese),
        ),
      );

      final mockAiClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'meaning': '(danh từ) phản bội đạo đức',
                    'pos': 'danh từ',
                    'sub_entries': [
                      {'word': '背徳的', 'meaning': '(tính từ) mang tính bội đức'},
                    ],
                  }),
                },
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final aiSettingsWithKey = AiSettings(
        activeService: AiServiceType.geminiCli,
        serviceConfigs: {
          AiServiceType.geminiCli: AiServiceConfig(
            keys: [AiApiKey('<API_KEY>')],
            selectedModel: 'gemini-3-flash-preview',
            requestDelay: 0,
          ),
        },
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((_) async => paths),
          dictionariesProvider.overrideWith(
            () => _MutableDicts(
              buildDicts(),
              onReload: () async => buildDicts(),
            ),
          ),
          aiSettingsControllerProvider.overrideWith(
            () => _TestAiSettingsNotifier(aiSettingsWithKey),
          ),
          aiApiClientProvider.overrideWithValue(
            AiApiClient(client: mockAiClient),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(dictionariesProvider.future);
      await container.read(aiSettingsControllerProvider.future);

      container.read(translationControllerProvider.notifier).translate(sentence);
      // Chọn từ qua selectRange như khi bôi đen từ trên ô Nguồn / VietPhrase.
      container.read(tokenSelectionProvider.notifier).selectRange(3, 5, word);

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        ),
      );

      final response = await tester.runAsync(
        () => executeAiLookup(capturedRef, word),
      );
      expect(response!.isSuccess, isTrue);

      // 1. Lưu VietPhrase_japanese.txt không chứa "(danh từ)" hay "(tính từ)".
      final vpOverlay = await tester.runAsync(
        () => service
            .vietPhraseOverlayFile(TranslationMode.japanese)
            .readAsString(),
      );
      expect(vpOverlay, contains('背徳=phản bội đạo đức'));
      expect(vpOverlay, contains('背徳的=mang tính bội đức'));
      expect(vpOverlay, isNot(contains('(danh từ)')));
      expect(vpOverlay, isNot(contains('(tính từ)')));

      // 2. Từ điển đã reload và văn bản nguồn đã dịch lại ngay.
      final translated = container
          .read(translationControllerProvider)
          .tokens
          .map((t) => t.meaning ?? t.source)
          .join(' ');
      expect(translated, contains('phản bội đạo đức'));

      // 3. Panel Nghĩa đã tự động cập nhật VietPhrase + AI Dịch (và giữ Phiên Âm English từ selectRange).
      final sections = container.read(lookupControllerProvider)!.sections;
      expect(
        sections.map((s) => s.label),
        containsAll(['VietPhrase', 'AI Dịch', 'Phiên Âm English']),
      );

      // 4. Từ con tách ra (背徳的) cũng tra được ngay trong VietPhrase và AI tách từ.
      container.read(lookupControllerProvider.notifier).lookup('背徳的');
      final subSections = container.read(lookupControllerProvider)!.sections;
      expect(
        subSections.map((s) => s.label),
        containsAll(['VietPhrase', 'AI tách từ']),
      );
    },
  );
}

