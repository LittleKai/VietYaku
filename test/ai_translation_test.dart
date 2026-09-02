import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/ai_translation/application/ai_lookup_controller.dart';
import 'package:vietyaku/features/ai_translation/data/ai_api_client.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_api_key.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_key_rotator.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_lookup_result.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_service_config.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_service_type.dart';
import 'package:vietyaku/features/dictionary/data/user_dict_service.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/domain/lookup_dictionary_type.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  group('AiServiceType & Models', () {
    test('Gemini CLI models match exactly', () {
      final models = AiServiceType.geminiCli.availableModels;
      expect(models, contains('gemini-3-flash-preview'));
      expect(models, contains('假流式-agy-gemini-3.6-flash-low'));
      expect(models.length, equals(12));
    });

    test('Gemini API models are accurate', () {
      final models = AiServiceType.geminiApi.availableModels;
      expect(models, contains('gemini-2.5-flash'));
      expect(models, contains('gemini-3-pro-preview'));
    });

    test('ChatGPT API models are accurate', () {
      final models = AiServiceType.chatGptApi.availableModels;
      expect(models, contains('gpt-4o-mini'));
      expect(models, contains('gpt-5'));
      // o-series đã bỏ: tham số khác hẳn chat model, chọn vào là lỗi 400.
      expect(models, isNot(contains('o1')));
      expect(models, isNot(contains('o3-mini')));
    });

    test('Claude API models are accurate', () {
      final models = AiServiceType.claudeApi.availableModels;
      expect(models, contains('claude-3-5-haiku-20241022'));
      expect(models, contains('claude-3-7-sonnet-20250219'));
    });

    test('Grok API models are accurate', () {
      final models = AiServiceType.grokApi.availableModels;
      expect(models, contains('grok-3-mini'));
      expect(models, contains('grok-4-fast-reasoning'));
      // grok-2 đã ngừng phục vụ trên xAI API.
      expect(models, isNot(contains('grok-2-latest')));
    });
  });

  group('AiServiceConfig & AiSettings', () {
    test('Masks API key securely', () {
      expect(AiSettings.maskKey('AIzaSyAxfa1234567890QkGw'), 'AIzaSy...QkGw');
      expect(AiSettings.maskKey('12345'), '*****');
    });

    test('Serializes and deserializes AiSettings correctly', () {
      final settings = AiSettings.defaults().copyWith(
        activeService: AiServiceType.geminiApi,
      );
      final json = settings.toJson();
      final decoded = AiSettings.fromJson(json);

      expect(decoded.activeService, equals(AiServiceType.geminiApi));
      expect(decoded.serviceConfigs.containsKey(AiServiceType.geminiApi), isTrue);
      expect(
        decoded.activeConfig.selectedModel,
        equals('gemini-3-flash-preview'),
      );
    });

    test('Parses legacy plain-string keys as weight 1', () {
      final config = AiServiceConfig.fromJson(const {
        'keys': ['key1', 'key2'],
        'selected_model': 'gpt-4o-mini',
      }, AiServiceType.chatGptApi);

      expect(config.keys.map((k) => k.value), equals(['key1', 'key2']));
      expect(config.keys.every((k) => k.weight == 1), isTrue);
    });

    test('Round-trips key weights through JSON', () {
      final config = AiServiceConfig(
        keys: [AiApiKey('key1', weight: 5), AiApiKey('key2')],
        selectedModel: 'gpt-4o-mini',
      );
      final decoded = AiServiceConfig.fromJson(
        config.toJson(),
        AiServiceType.chatGptApi,
      );

      expect(decoded.keys[0].weight, equals(5));
      expect(decoded.keys[1].weight, equals(1));
    });

    test('Clamps weight into the allowed range', () {
      expect(AiApiKey('k', weight: 0).weight, equals(AiApiKey.minWeight));
      expect(AiApiKey('k', weight: -7).weight, equals(AiApiKey.minWeight));
      expect(AiApiKey('k', weight: 9999).weight, equals(AiApiKey.maxWeight));
    });
  });

  group('AiKeyRotator', () {
    test('Rotates through keys instead of repeating one', () {
      final rotator = AiKeyRotator();
      final keys = [AiApiKey('a'), AiApiKey('b'), AiApiKey('c')];

      final picked = [
        for (var i = 0; i < 3; i++) rotator.next(keys)!.value,
      ];
      expect(picked.toSet(), equals({'a', 'b', 'c'}));
    });

    test('Honours weight ratio over a full cycle', () {
      final rotator = AiKeyRotator();
      final keys = [AiApiKey('heavy', weight: 3), AiApiKey('light')];

      final counts = <String, int>{};
      // Một chu kỳ = tổng weight = 4 lượt; chạy 3 chu kỳ cho chắc.
      for (var i = 0; i < 12; i++) {
        final key = rotator.next(keys)!;
        counts[key.value] = (counts[key.value] ?? 0) + 1;
      }

      expect(counts['heavy'], equals(9));
      expect(counts['light'], equals(3));
    });

    test('Spreads the heavy key instead of bursting it', () {
      final rotator = AiKeyRotator();
      final keys = [AiApiKey('heavy', weight: 2), AiApiKey('light')];

      final picked = [
        for (var i = 0; i < 6; i++) rotator.next(keys)!.value,
      ];
      // Không được có 3 lượt liên tiếp cùng một key.
      for (var i = 0; i + 2 < picked.length; i++) {
        expect(
          picked[i] == picked[i + 1] && picked[i + 1] == picked[i + 2],
          isFalse,
          reason: 'Bị dồn cục tại vị trí $i: $picked',
        );
      }
    });

    test('Skips unavailable keys and returns null when all are skipped', () {
      final rotator = AiKeyRotator();
      final keys = [AiApiKey('a'), AiApiKey('b')];

      expect(rotator.next(keys, skip: {'a'})!.value, equals('b'));
      expect(rotator.next(keys, skip: {'a', 'b'}), isNull);
    });
  });

  group('AiApiClient HTTP requests', () {
    test('Calls Gemini CLI proxy successfully', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/v1/chat/completions'));
        expect(request.headers['Authorization'], equals('Bearer test-gcli-key'));
        final body = jsonDecode(request.body);
        expect(body['model'], equals('gemini-3-flash-preview'));

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Phân tích từ ngữ tiếng Nhật'},
                'finish_reason': 'stop',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = AiApiClient(client: mockClient);
      final config = AiServiceConfig(
        keys: [AiApiKey('test-gcli-key')],
        selectedModel: 'gemini-3-flash-preview',
        proxyUrl: 'https://gcli.ggchan.dev',
      );

      final response = await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.geminiCli,
        config: config,
      );

      expect(response.isSuccess, isTrue);
      expect(response.text, equals('Phân tích từ ngữ tiếng Nhật'));
    });

    test('Calls Gemini API direct successfully', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('generativelanguage.googleapis.com'));
        expect(request.url.queryParameters['key'], equals('AIzaSyTest123'));
        final body = jsonDecode(request.body);
        expect(body['contents'][0]['parts'][0]['text'], contains('Tra từ'));

        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '1. Nghĩa tiếng Việt: Giác ngộ, chuẩn bị tinh thần.'}
                  ]
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = AiApiClient(client: mockClient);
      final config = AiServiceConfig(
        keys: [AiApiKey('AIzaSyTest123')],
        selectedModel: 'gemini-2.5-flash',
      );

      final response = await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.geminiApi,
        config: config,
      );

      expect(response.isSuccess, isTrue);
      expect(response.text, contains('Giác ngộ'));
    });

    test('Marks key as failed on 401 or 403 and returns error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Invalid API Key', 401);
      });

      final apiClient = AiApiClient(client: mockClient);
      final config = AiServiceConfig(
        keys: [AiApiKey('bad-key-1234567890')],
        selectedModel: 'gemini-2.5-flash',
      );

      final response = await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.geminiApi,
        config: config,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error, contains('401'));
      expect(apiClient.failedKeys, contains('bad-key-1234567890'));
    });

    test('Rotates to the next key when one hits 429', () async {
      final tried = <String>[];
      final mockClient = MockClient((request) async {
        final key = request.url.queryParameters['key']!;
        tried.add(key);
        if (key == 'exhausted-key-000') {
          return http.Response('Quota exceeded', 429);
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Nghĩa từ key dự phòng'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = AiApiClient(client: mockClient);
      final config = AiServiceConfig(
        keys: [AiApiKey('exhausted-key-000'), AiApiKey('good-key-11111')],
        selectedModel: 'gemini-2.5-flash',
      );

      final response = await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.geminiApi,
        config: config,
      );

      expect(response.isSuccess, isTrue);
      expect(response.text, equals('Nghĩa từ key dự phòng'));
      expect(tried, contains('exhausted-key-000'));
      expect(tried.last, equals('good-key-11111'));
      expect(apiClient.failedKeys, contains('exhausted-key-000'));
    });

    test('resetFailedKeys puts a cooled-down key back in rotation', () async {
      final mockClient = MockClient(
        (request) async => http.Response('Invalid API Key', 401),
      );
      final apiClient = AiApiClient(client: mockClient);
      final config = AiServiceConfig(
        keys: [AiApiKey('bad-key-1234567890')],
        selectedModel: 'gemini-2.5-flash',
      );

      await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.geminiApi,
        config: config,
      );
      expect(apiClient.failedKeys, isNotEmpty);

      apiClient.resetFailedKeys();
      expect(apiClient.failedKeys, isEmpty);
    });

    test('OpenAI reasoning model uses max_completion_tokens only', () async {
      Map<String, dynamic>? sent;
      final mockClient = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = AiApiClient(client: mockClient);
      await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.chatGptApi,
        config: AiServiceConfig(
          keys: [AiApiKey('sk-test-key-000000')],
          selectedModel: 'gpt-5-mini',
        ),
      );

      expect(sent!.containsKey('max_completion_tokens'), isTrue);
      expect(sent!.containsKey('max_tokens'), isFalse);
      expect(sent!.containsKey('temperature'), isFalse);
      expect(sent!.containsKey('top_p'), isFalse);
    });

    test('OpenAI non-reasoning model keeps max_tokens + temperature', () async {
      Map<String, dynamic>? sent;
      final mockClient = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = AiApiClient(client: mockClient);
      await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.chatGptApi,
        config: AiServiceConfig(
          keys: [AiApiKey('sk-test-key-000000')],
          selectedModel: 'gpt-4o-mini',
        ),
      );

      expect(sent!.containsKey('max_tokens'), isTrue);
      expect(sent!.containsKey('temperature'), isTrue);
      expect(sent!.containsKey('max_completion_tokens'), isFalse);
    });

    test('Claude payload never sends temperature and top_p together', () async {
      Map<String, dynamic>? sent;
      final mockClient = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'content': [
              {'text': 'ok'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = AiApiClient(client: mockClient);
      await apiClient.callAi(
        prompt: 'Tra từ 覚悟',
        serviceType: AiServiceType.claudeApi,
        config: AiServiceConfig(
          keys: [AiApiKey('sk-ant-test-000000')],
          selectedModel: 'claude-sonnet-4-5-20250929',
        ),
      );

      expect(sent!.containsKey('temperature'), isTrue);
      expect(sent!.containsKey('top_p'), isFalse);
    });
  });

  group('AiLookupController & Prompt Builder', () {
    test('Japanese prompt asks for JSON with stem rule', () {
      final prompt = buildAiLookupPrompt(
        '立ち入り禁止',
        mode: TranslationMode.japanese,
      );
      expect(prompt, contains('tiếng Nhật'));
      expect(prompt, contains('立ち入り禁止'));
      expect(prompt, contains('JSON'));
      expect(prompt, contains('"sub_entries"'));
      // Quy tắc bỏ đuôi い để engine detect được thân từ.
      expect(prompt, contains('チャラい → チャラ'));
    });

    test('Chinese prompt dùng đúng ngôn ngữ và từ được tra', () {
      final prompt = buildAiLookupPrompt('破釜沉舟', mode: TranslationMode.chinese);
      expect(prompt, contains('tiếng Trung'));
      expect(prompt, contains('破釜沉舟'));
    });

    test('Prompt cấm phiên âm và âm Hán Việt ở cả hai mode', () {
      for (final mode in TranslationMode.values) {
        final prompt = buildAiLookupPrompt('テスト', mode: mode);
        expect(prompt, contains('KHÔNG đưa phiên âm'));
        expect(prompt, isNot(contains('"romaji"')));
        expect(prompt, isNot(contains('"han_viet"')));
        expect(prompt, isNot(contains('"reading"')));
      }
    });

    test('Prompt forbids usage examples in both modes', () {
      for (final mode in TranslationMode.values) {
        final prompt = buildAiLookupPrompt('テスト', mode: mode);
        expect(prompt, contains('Không đưa câu ví dụ'));
        expect(prompt, isNot(contains('Ví dụ sử dụng')));
      }
    });
  });

  group('AiLookupResult JSON parsing', () {
    test('Parses full JSON payload', () {
      final result = AiLookupResult.tryParse(
        'この人こんなにチャラかった',
        '{"meaning":"Người này lăng nhăng đến mức này","pos":"cụm câu",'
            '"parts":[{"part":"チャラかった","base":"チャラい",'
            '"meaning":"lăng nhăng (quá khứ)"}],'
            '"sub_entries":[{"word":"チャラ","meaning":"lăng nhăng/cợt nhả"}]}',
      );

      expect(result, isNotNull);
      expect(result!.meaning, contains('lăng nhăng'));
      expect(result.parts.single.base, equals('チャラい'));
      expect(result.subEntries.single.word, equals('チャラ'));
    });

    test('Bỏ qua phiên âm / Hán Việt nếu model vẫn trả về', () {
      final result = AiLookupResult.tryParse(
        'チャラ',
        '{"meaning":"lăng nhăng","reading":"チャラ","romaji":"chara",'
            '"han_viet":"Nhân"}',
      );

      final md = result!.toMarkdown();
      expect(md, isNot(contains('chara')));
      expect(md, isNot(contains('Hán Việt')));
      expect(result.toStorageValue(), isNot(contains('romaji')));
      expect(result.toStorageValue(), isNot(contains('han_viet')));
    });

    test('Không lưu sub_entries vào AiDict', () {
      const result = AiLookupResult(
        word: 'チャラ',
        meaning: 'lăng nhăng',
        subEntries: [AiSubEntry('チャラい', 'lăng nhăng (tính từ)')],
      );
      final stored = result.toStorageValue();

      // sub_entries đã thành mục từ điển riêng ngay lúc tra; giữ lại đây thì
      // mỗi lần mở lại ô Nghĩa sẽ hiện thừa mục "Đã thêm vào từ điển".
      expect(stored, isNot(contains('sub_entries')));
      expect(stored, isNot(contains('チャラい')));
      expect(
        aiBodyToMarkdown('チャラ', stored),
        isNot(contains('Đã thêm vào từ điển')),
      );
    });

    test('Tolerates ```json fences and surrounding prose', () {
      final result = AiLookupResult.tryParse(
        'テスト',
        'Đây là kết quả:\n```json\n{"meaning":"thử nghiệm"}\n```\nHết.',
      );
      expect(result?.meaning, equals('thử nghiệm'));
    });

    test('Drops a sub_entry that repeats the looked-up word', () {
      final result = AiLookupResult.tryParse(
        'チャラ',
        '{"meaning":"lăng nhăng","sub_entries":['
            '{"word":"チャラ","meaning":"lăng nhăng"},'
            '{"word":"チャラい","meaning":"lăng nhăng (tính từ)"}]}',
      );
      expect(result!.subEntries.map((e) => e.word), equals(['チャラい']));
    });

    test('Skips malformed sub_entries instead of failing the whole parse', () {
      final result = AiLookupResult.tryParse(
        'テスト',
        '{"meaning":"thử","sub_entries":[{"word":""},"rác",'
            '{"word":"テス","meaning":"thử"}]}',
      );
      expect(result!.subEntries.single.word, equals('テス'));
    });

    test('Returns null when there is no JSON or no meaning', () {
      expect(AiLookupResult.tryParse('x', '### Nghĩa\n- markdown thuần'), isNull);
      expect(AiLookupResult.tryParse('x', '{"pos":"danh từ"}'), isNull);
    });

    test('Storage value is single-line JSON that round-trips', () {
      const source = AiLookupResult(
        word: 'チャラ',
        meaning: 'lăng nhăng/cợt nhả',
        partOfSpeech: 'tính từ',
        parts: [AiPart('チャラ', meaning: 'thân từ')],
        subEntries: [AiSubEntry('チャラい', 'lăng nhăng')],
      );
      final stored = source.toStorageValue();

      expect(stored, isNot(contains('\n')));
      final decoded = AiLookupResult.tryParse('チャラ', stored);
      expect(decoded!.meaning, equals('lăng nhăng/cợt nhả'));
      expect(decoded.partOfSpeech, equals('tính từ'));
      expect(decoded.parts.single.part, equals('チャラ'));
      // sub_entries cố ý KHÔNG round-trip — đã thành mục từ điển riêng rồi.
      expect(decoded.subEntries, isEmpty);
    });

    test('Renders Markdown from the structured result', () {
      const result = AiLookupResult(
        word: 'チャラかった',
        meaning: 'lăng nhăng',
        parts: [AiPart('チャラかった', base: 'チャラい', meaning: 'thì quá khứ')],
        subEntries: [AiSubEntry('チャラ', 'lăng nhăng')],
      );
      final md = result.toMarkdown();

      expect(md, contains('**lăng nhăng**'));
      expect(md, contains('← チャラい'));
      expect(md, contains('**チャラ** — lăng nhăng'));
    });

    test('aiBodyToMarkdown passes legacy Markdown bodies through', () {
      const legacy = '### 1. Nghĩa tiếng Việt:\n*   **Dịch sát nghĩa:** ...';
      expect(aiBodyToMarkdown('x', legacy), equals(legacy));
    });

    test('aiBodyToMarkdown renders a stored JSON body', () {
      final rendered = aiBodyToMarkdown('チャラ', '{"meaning":"lăng nhăng"}');
      expect(rendered, contains('**lăng nhăng**'));
      expect(rendered, isNot(contains('{')));
    });
  });

  group('AiDict persistence & Local Lookup integration', () {
    late Directory tempDir;
    late AppPaths paths;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vietyaku_ai_dict_test_');
      paths = AppPaths(tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Upserts to AiDict_<mode>.txt and decodes properly', () async {
      final service = UserDictService(paths);
      const word = '覚悟';
      final encodedBody = encodeOnlineSections([
        const LookupSection(word, 'AI Dịch', 'Giác ngộ; sẵn sàng đối mặt.'),
      ]);

      await service.upsertAiDict(TranslationMode.japanese, word, encodedBody);

      final aiDictFile = service.aiDictFile(TranslationMode.japanese);
      expect(aiDictFile.existsSync(), isTrue);

      final content = await aiDictFile.readAsString();
      expect(content, contains('覚悟=<<AI Dịch>>'));

      // Decode test
      final sections = decodeOnlineSections(word, encodedBody);
      expect(sections.length, equals(1));
      expect(sections.first.label, equals('AI Dịch'));
      expect(sections.first.body, equals('Giác ngộ; sẵn sàng đối mặt.'));
      expect(LookupDictionaryType.ai.matchesLabel(sections.first.label), isTrue);
    });

    test('Writes AiEntries and VietPhrase overlay beside AiDict', () async {
      final service = UserDictService(paths);
      const mode = TranslationMode.japanese;

      await service.upsertAiEntries(mode, {
        'チャラ': 'lăng nhăng/cợt nhả',
        'チャラい': 'lăng nhăng (tính từ)',
      });
      await service.upsertVietPhraseOverlay(mode, {
        'チャラ': 'lăng nhăng/cợt nhả',
      });

      final entries = await service.aiEntriesFile(mode).readAsString();
      expect(entries, contains('チャラ=lăng nhăng/cợt nhả'));
      expect(entries, contains('チャラい=lăng nhăng (tính từ)'));

      final overlay = await service
          .vietPhraseOverlayFile(mode)
          .readAsString();
      expect(overlay, contains('チャラ=lăng nhăng/cợt nhả'));
    });

    test('inDir routes writes to the shared generated folder', () async {
      final service = UserDictService(paths);
      const mode = TranslationMode.japanese;
      final shared = Directory(
        p.join(tempDir.path, 'data', 'jp', 'generated'),
      ).path;

      await service.upsertAiDict(mode, '覚悟', 'x', inDir: shared);
      await service.upsertAiEntries(mode, {'覚': 'giác'}, inDir: shared);
      await service.upsertVietPhraseOverlay(
        mode,
        {'覚': 'giác'},
        inDir: shared,
      );

      expect(service.aiDictFile(mode, inDir: shared).existsSync(), isTrue);
      expect(service.aiEntriesFile(mode, inDir: shared).existsSync(), isTrue);
      expect(
        service.vietPhraseOverlayFile(mode, inDir: shared).existsSync(),
        isTrue,
      );
      // Không đụng bản cá nhân trong userdata.
      expect(service.aiDictFile(mode).existsSync(), isFalse);
      expect(service.vietPhraseOverlayFile(mode).existsSync(), isFalse);
    });

    test('removeGeneratedEntry xoá từ AI tạo khỏi cả hai overlay', () async {
      final service = UserDictService(paths);
      const mode = TranslationMode.chinese;
      // Đúng ca người dùng gặp: từ do AI tạo, bấm "Xóa từ" nhưng vẫn được dịch.
      const word = '比如铸铁者的冷面锡德';

      await service.upsertVietPhraseOverlay(mode, {
        word: 'ví dụ như Sid mặt lạnh của thợ đúc',
        '幸福': 'hạnh phúc',
      });
      await service.upsertAiEntries(mode, {word: 'x', '幸福': 'hạnh phúc'});

      expect(await service.removeGeneratedEntry(mode, word), isTrue);

      final overlay = await service
          .vietPhraseOverlayFile(mode)
          .readAsString();
      final entries = await service.aiEntriesFile(mode).readAsString();
      expect(overlay, isNot(contains(word)));
      expect(entries, isNot(contains(word)));
      // Không đụng các mục khác.
      expect(overlay, contains('幸福=hạnh phúc'));
      expect(entries, contains('幸福=hạnh phúc'));
    });

    test('removeGeneratedEntry báo false khi không có gì để xoá', () async {
      final service = UserDictService(paths);
      expect(
        await service.removeGeneratedEntry(TranslationMode.japanese, '未登録'),
        isFalse,
      );
    });

    test('removeGeneratedEntry KHÔNG đụng AiDict đã lưu', () async {
      final service = UserDictService(paths);
      const mode = TranslationMode.japanese;
      const word = 'チャラ';

      await service.upsertAiDict(mode, word, 'phân tích đã tra');
      await service.upsertVietPhraseOverlay(mode, {word: 'lăng nhăng'});
      await service.removeGeneratedEntry(mode, word);

      // Xoá mục dịch không có nghĩa là vứt luôn kết quả tra cứu.
      expect(await service.aiDictFile(mode).readAsString(), contains(word));
    });

    test('removeGeneratedEntry chỉ khớp nguyên key, không khớp tiền tố', () async {
      final service = UserDictService(paths);
      const mode = TranslationMode.japanese;

      await service.upsertVietPhraseOverlay(mode, {
        'チャラ': 'lăng nhăng',
        'チャラい': 'lăng nhăng (tính từ)',
      });
      await service.removeGeneratedEntry(mode, 'チャラ');

      final overlay = await service
          .vietPhraseOverlayFile(mode)
          .readAsString();
      expect(overlay, contains('チャラい='));
      expect(overlay, isNot(contains('\nチャラ=')));
    });

    test('Upsert replaces the value of an existing key', () async {
      final service = UserDictService(paths);
      const mode = TranslationMode.japanese;

      await service.upsertAiEntries(mode, {'チャラ': 'nghĩa cũ'});
      await service.upsertAiEntries(mode, {'チャラ': 'nghĩa mới'});

      final content = await service.aiEntriesFile(mode).readAsString();
      expect(content, contains('チャラ=nghĩa mới'));
      expect(content, isNot(contains('nghĩa cũ')));
    });
  });
}
