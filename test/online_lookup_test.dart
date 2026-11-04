import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/core/google_translate.dart';
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
import 'package:vietyaku/features/translation/application/online_lookup_controller.dart';
import 'package:vietyaku/features/translation/data/jisho_api.dart';
import 'package:vietyaku/features/translation/data/weblio_api.dart';
import 'package:vietyaku/features/translation/data/youdao_api.dart';
import 'package:vietyaku/features/translation/domain/online_lookup_source.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/presentation/lacviet_panel.dart';

class _TestDictionariesNotifier extends DictionariesNotifier {
  _TestDictionariesNotifier(this.loaded);
  LoadedDictionaries loaded;

  @override
  Future<LoadedDictionaries> build() async => loaded;

  @override
  Future<void> reload() async {}
}

class _TestAiSettingsNotifier extends AiSettingsController {
  _TestAiSettingsNotifier(this.initial);
  final AiSettings initial;

  @override
  Future<AiSettings> build() async => initial;
}

void main() {
  group('OnlineDict encode/decode', () {
    test('giữ nguyên các mục qua 1 vòng encode → decode', () {
      const sections = [
        LookupSection('取り消し', 'Mazii Online', '取り消し「とりけし」\n- (danh từ) hủy bỏ'),
        LookupSection('取り消し', 'Google Dịch', 'hủy bỏ'),
        LookupSection('取り消し', 'Google Anh', 'cancellation'),
      ];

      final value = encodeOnlineSections(sections);
      // Value dict phải nằm trọn 1 dòng (xuống dòng escape như LacViet).
      expect(value.contains('\n'), isFalse);

      final decoded = decodeOnlineSections('取り消し', value);
      expect(decoded.map((s) => s.label), [
        'Mazii Online',
        'Google Dịch',
        'Google Anh',
      ]);
      expect(decoded.map((s) => s.body), sections.map((s) => s.body));
      expect(decoded.every((s) => s.word == '取り消し'), isTrue);
    });

    test('bỏ qua mục rỗng và nội dung trước nhãn đầu tiên', () {
      final decoded = decodeOnlineSections(
        '猫',
        r'rác\n<<Google Dịch>>\ncon mèo\n<<Google Anh>>\n',
      );
      expect(decoded, hasLength(1));
      expect(decoded.single.label, 'Google Dịch');
      expect(decoded.single.body, 'con mèo');
    });
  });

  test('JishoApi.format: header + nghĩa theo từ loại', () {
    final body = JishoApi.format(const {
      'is_common': true,
      'jlpt': ['jlpt-n5'],
      'japanese': [
        {'word': '猫', 'reading': 'ねこ'},
      ],
      'senses': [
        {
          'english_definitions': ['cat', 'feline'],
          'parts_of_speech': ['Noun'],
        },
        {
          'english_definitions': ['shamisen'],
          'parts_of_speech': ['Noun'],
        },
      ],
    });
    expect(
      body,
      '猫 「ねこ」 (thường dùng, N5)\n- (Noun) cat; feline\n- (Noun) shamisen',
    );
  });

  test('JishoApi.format: không có nghĩa nào thì trả null', () {
    expect(
      JishoApi.format(const {
        'japanese': [
          {'word': '猫'},
        ],
        'senses': [],
      }),
      isNull,
    );
  });

  group('WeblioApi.format (meta description thật của cjjc.weblio.jp)', () {
    test('tách nhãn thành dòng, bỏ tiền tố và đuôi giới thiệu site', () {
      const html =
          '<meta name="description" content="勉強の意味や日本語訳。中国語訳功课ピンインgōngkè'
          ' - 約160万語の日中中日辞典。読み方・発音も分かる中国語辞書。">';
      expect(WeblioApi.format(html, '勉強'), '中国語訳 功课\nピンイン gōngkè');
    });

    test('tiền tố "〜の中国語訳。" cũng bị bỏ', () {
      const html =
          '<meta name="description" content="取り消しの中国語訳。読み方とりけし中国語訳取消，废除'
          '中国語品詞動詞 - 約160万語の日中中日辞典。">';
      expect(WeblioApi.format(html, '取り消し'), '読み方 とりけし\n中国語訳 取消，废除\n中国語品詞 動詞');
    });

    test('không có thẻ description thì trả null', () {
      expect(WeblioApi.format('<html><body>404</body></html>', '猫'), isNull);
    });
  });

  group('YoudaoApi.format (response thật của dict.youdao.com/jsonapi)', () {
    /// Một nghĩa: `l.i` là các mảnh, mảnh tra được là map có `#text`.
    Map<String, dynamic> sense(List<Object> parts, [String? pos]) => {
      'tr': [
        {
          'l': {'i': parts, 'pos': ?pos},
        },
      ],
    };

    test('header có pinyin, mỗi nghĩa một dòng kèm từ loại', () {
      final json = {
        'ce': {
          'word': [
            {
              'return-phrase': {
                'l': {'i': '取消'},
              },
              'phone': 'qǔ xiāo',
              'trs': [
                sense(['', 'cancel'], 'vt.'),
                // "call off" bị chẻ làm 2 mảnh tra được + 1 space.
                sense([
                  '',
                  {'#text': 'call'},
                  ' ',
                  {'#text': 'off'},
                ]),
              ],
            },
          ],
        },
      };
      expect(
        YoudaoApi.format(json, '取消'),
        '取消 「qǔ xiāo」\n- (vt.) cancel\n- call off',
      );
    });

    test('phồn thể: header hiện headword giản thể mà Youdao quy về', () {
      final json = {
        'ce': {
          'word': [
            {
              'return-phrase': {
                'l': {'i': '时间'},
              },
              'phone': 'shí jiān',
              'trs': [
                sense(['', 'time'], 'n.'),
              ],
            },
          ],
        },
      };
      expect(YoudaoApi.format(json, '時間'), '时间 「shí jiān」\n- (n.) time');
    });

    test('không có phone thì header chỉ có headword', () {
      final json = {
        'ce': {
          'word': [
            {
              'return-phrase': {
                'l': {'i': '电车'},
              },
              'trs': [
                sense(['', 'tram']),
              ],
            },
          ],
        },
      };
      expect(YoudaoApi.format(json, '电车'), '电车\n- tram');
    });

    test('từ không có trong từ điển: response thiếu khoá ce → null', () {
      expect(
        YoudaoApi.format(const {
          'input': '一露头',
          'meta': {'guessLanguage': 'zh'},
        }, '一露头'),
        isNull,
      );
    });
  });

  test('nguồn tra online mặc định bật cả 4, bật/tắt được từng nguồn', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsProvider).onlineLookupSources,
      OnlineLookupSource.values,
    );

    await container.read(settingsProvider.notifier).setOnlineLookupSources(
      const [OnlineLookupSource.english, OnlineLookupSource.mazii],
    );
    // Giữ thứ tự khai báo của enum, không theo thứ tự truyền vào.
    expect(container.read(settingsProvider).onlineLookupSources, const [
      OnlineLookupSource.mazii,
      OnlineLookupSource.english,
    ]);

    await container
        .read(settingsProvider.notifier)
        .setOnlineLookupSources(const []);
    expect(container.read(settingsProvider).onlineLookupSources, isEmpty);
  });

  test(
    'lookupWeblioWithGoogle tự động dịch nội dung Weblio 日中 sang tiếng Việt bằng Google Dịch',
    () async {
      final weblioClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            '<meta name="description" content="カッターの意味や日本語訳。中国語訳车刀ピンインchēdāo - 約160万語の日中中日辞典。">',
          ),
          200,
        );
      });
      final googleClient = MockClient((request) async {
        expect(request.url.queryParameters['sl'], 'zh-CN');
        expect(request.url.queryParameters['q'], '车刀');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              [
                ['dụng cụ tiện', '车刀'],
              ],
            ]),
          ),
          200,
        );
      });

      final out = await lookupWeblioWithGoogle(
        WeblioApi(client: weblioClient),
        GoogleTranslateClient(client: googleClient),
        'カッター',
      );
      expect(out, 'Nghĩa: dụng cụ tiện\nPinyin: chēdāo');
      expect(isRawWeblioBody(out!), isFalse);
    },
  );

  testWidgets(
    'Weblio 日中 ban đầu tự động dùng Google Dịch, khi bấm Dịch AI thì thay thế bản Google Dịch',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('weblio_ai_test_');
      addTearDown(() {
        try {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final paths = AppPaths(tempDir);
      final service = UserDictService(paths);
      const word = '取り消し';
      final initialOnline = encodeOnlineSections(const [
        LookupSection(word, 'Mazii Online', 'hủy bỏ (Mazii)'),
        LookupSection(word, 'Weblio 日中', '読み方 とりけし\n中国語訳 取消，废除'),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await tester.runAsync(() async {
        await service.upsertOnlineDict(
          TranslationMode.japanese,
          word,
          initialOnline,
        );
      });

      PhraseDictionary d(DictType t, [Map<String, String> e = const {}]) =>
          PhraseDictionary(t, e);
      final dicts = LoadedDictionaries(
        userDict: d(DictType.userDict),
        names: d(DictType.names),
        vietPhrase: d(DictType.vietPhrase),
        lacViet: d(DictType.lacViet),
        chinesePhienAm: d(DictType.chinesePhienAm),
        pronouns: d(DictType.pronouns),
        babylon: d(DictType.babylon),
        thieuChuu: d(DictType.thieuChuu),
        cedict: d(DictType.cedict),
        chinesePhienAmEnglish: d(DictType.chinesePhienAmEnglish),
        jaVi: d(DictType.jaVi),
        zhVi: d(DictType.zhVi),
        onlineDict: d(DictType.onlineDict, {word: initialOnline}),
        stats: const {},
      );

      final mockGoogleClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              [
                ['hủy bỏ (Google)', '取消，废除'],
              ],
            ]),
          ),
          200,
        );
      });

      String? capturedAiPrompt;
      final mockAiClient = MockClient((request) async {
        final bodyJson = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = bodyJson['messages'] as List<dynamic>;
        capturedAiPrompt =
            (messages.first as Map<String, dynamic>)['content'] as String;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': 'Cách đọc: とりけし\nNghĩa: hủy bỏ, bãi bỏ (AI)',
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
            () => _TestDictionariesNotifier(dicts),
          ),
          googleTranslateProvider.overrideWithValue(
            GoogleTranslateClient(client: mockGoogleClient),
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
      container.read(lookupControllerProvider.notifier).lookup(word);

      Future<void> pumpUntilFound(Finder finder) async {
        for (var i = 0; i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: LacVietPanel())),
        ),
      );
      await pumpUntilFound(find.textContaining('Nghĩa: hủy bỏ (Google)'));

      // Ban đầu tự động dịch qua Google Dịch và lưu vào OnlineDict.
      expect(find.text('Dịch AI'), findsOneWidget);
      expect(find.textContaining('Nghĩa: hủy bỏ (Google)'), findsOneWidget);
      final googleSavedRaw = await tester.runAsync(
        () => service.onlineDictFile(TranslationMode.japanese).readAsString(),
      );
      expect(googleSavedRaw, contains('Nghĩa: hủy bỏ (Google)'));

      // Khi nhấn Dịch AI thì dịch từ bản gốc Weblio và thay thế cho bản Google Dịch.
      await tester.tap(find.text('Dịch AI'));
      await pumpUntilFound(find.textContaining('Nghĩa: hủy bỏ, bãi bỏ (AI)'));

      expect(capturedAiPrompt, contains('中国語訳 取消，废除'));
      expect(find.textContaining('Nghĩa: hủy bỏ (Google)'), findsNothing);
      expect(find.textContaining('Nghĩa: hủy bỏ, bãi bỏ (AI)'), findsOneWidget);

      // File OnlineDict_japanese.txt được thay thế bằng bản dịch AI và giữ nguyên Mazii Online.
      final savedRaw = await tester.runAsync(
        () => service.onlineDictFile(TranslationMode.japanese).readAsString(),
      );
      expect(savedRaw, contains('<<Mazii Online>>'));
      expect(savedRaw, contains('hủy bỏ (Mazii)'));
      expect(savedRaw, contains('<<Weblio 日中>>'));
      expect(savedRaw, isNot(contains('Nghĩa: hủy bỏ (Google)')));
      expect(savedRaw, contains('Nghĩa: hủy bỏ, bãi bỏ (AI)'));
    },
  );
}
