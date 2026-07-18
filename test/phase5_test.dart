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
      final entries = parseEntries(service.userDictFile.readAsStringSync());
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
    final engine = TranslationEngine(
      dicts: [
        PhraseDictionary(DictType.userDict, {'覚悟': 'nghĩa user'}),
        PhraseDictionary(DictType.names, {'覚悟': 'nghĩa names'}),
        PhraseDictionary(DictType.vietPhrase, {'覚悟': 'nghĩa vp'}),
      ],
    );
    final tokens = engine.translate('覚悟');
    expect(tokens.single.meaning, 'nghĩa user');
    expect(tokens.single.dictType, DictType.userDict);
  });
}
