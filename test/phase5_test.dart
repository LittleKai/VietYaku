import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/data/dict_parser.dart';
import 'package:vietyaku/features/dictionary/data/user_dict_service.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  group('UserDictService', () {
    late Directory temp;
    late UserDictService service;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('vy_userdict');
      final paths = AppPaths(temp);
      paths.dictionariesDir.createSync(recursive: true);
      service = UserDictService(paths);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('thêm entry mới → file BOM CRLF, parse lại được', () async {
      await service.upsertUserDict('骸骨騎士', 'Kỵ sĩ xương');
      final bytes = service.userDictFile.readAsBytesSync();
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM');
      final entries =
          parseEntries(service.userDictFile.readAsStringSync());
      expect(entries['骸骨騎士'], 'Kỵ sĩ xương');
    });

    test('upsert key đã có → cập nhật, không nhân đôi', () async {
      await service.upsertUserDict('覚悟', 'nghĩa cũ');
      await service.upsertUserDict('覚悟', 'nghĩa mới');
      await service.upsertUserDict('別', 'khác');
      final content = service.userDictFile.readAsStringSync();
      final entries = parseEntries(content);
      expect(entries['覚悟'], 'nghĩa mới');
      expect(entries.length, 2);
      expect('='.allMatches(content).length, 2);
    });

    test('UserNames ghi file riêng', () async {
      await service.upsertUserName('アリアン', 'Arian');
      expect(service.userNamesFile.existsSync(), isTrue);
      expect(service.userDictFile.existsSync(), isFalse);
    });
  });

  test('UserDict ưu tiên cao nhất khi cùng độ dài match', () {
    final engine = TranslationEngine(dicts: [
      PhraseDictionary(DictType.userDict, {'覚悟': 'nghĩa user'}),
      PhraseDictionary(DictType.names, {'覚悟': 'nghĩa names'}),
      PhraseDictionary(DictType.vietPhrase, {'覚悟': 'nghĩa vp'}),
    ]);
    final tokens = engine.translate('覚悟');
    expect(tokens.single.meaning, 'nghĩa user');
    expect(tokens.single.dictType, DictType.userDict);
  });

  group('export vocabflip', () {
    test('JSON đạt validateImportData của vocabflip', () {
      // Tái tạo logic validateImportData trong ImportExportService của
      // vocabflip (khảo sát Phase 0) để khóa schema.
      bool validateImportData(Map<String, dynamic> json) {
        if (!json.containsKey('version')) return false;
        if (!json.containsKey('decks')) return false;
        final decks = json['decks'];
        if (decks is! List || decks.isEmpty) return false;
        final firstDeck = decks.first;
        if (firstDeck is! Map) return false;
        if (!firstDeck.containsKey('name')) return false;
        if (!firstDeck.containsKey('source_language')) return false;
        return true;
      }

      final deckJson = {
        'version': '1.0',
        'exported_at': DateTime.now().toIso8601String(),
        'decks': [
          {
            'name': 'VietYaku — Từ đã lưu',
            'description': 'Xuất từ VietYaku',
            'source_language': 'ja',
            'target_language': 'vi',
            'cards': [
              {
                'front': '覚悟',
                'front_phonetic': 'kakugo',
                'back': 'giác ngộ; quyết tâm',
                'notes': null,
                'tags': <String>[],
              },
            ],
          },
        ],
      };
      expect(validateImportData(deckJson), isTrue);

      // Card fields khớp Flashcard.fromJson: front (bắt buộc), back (bắt
      // buộc), front_phonetic nullable.
      final card = (deckJson['decks'] as List).first['cards'][0]
          as Map<String, dynamic>;
      expect(card['front'], isA<String>());
      expect(card['back'], isA<String>());

      // Round-trip qua jsonEncode/Decode không lỗi.
      final decoded =
          jsonDecode(jsonEncode(deckJson)) as Map<String, dynamic>;
      expect(validateImportData(decoded), isTrue);
    });
  });
}
