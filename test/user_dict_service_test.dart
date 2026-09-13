import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/data/user_dict_service.dart';

void main() {
  late Directory tempDir;
  late AppPaths paths;
  late UserDictService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('user_dict_service_test');
    paths = AppPaths(tempDir);
    service = UserDictService(paths);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('UserDictService.removeUserName', () {
    test('Xóa thành công key đã tồn tại trong UserNames.txt và giữ nguyên BOM', () async {
      await service.upsertUserName('佐助', 'Sasuke');
      await service.upsertUserName('鳴人', 'Naruto');

      expect(service.userNamesFile.existsSync(), isTrue);

      final removed = await service.removeUserName('佐助');
      expect(removed, isTrue);

      final bytes = await service.userNamesFile.readAsBytes();
      expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
      final content = await service.userNamesFile.readAsString();
      expect(content.contains('佐助='), isFalse);
      expect(content.contains('鳴人=Naruto'), isTrue);
    });

    test('Trả về false khi key không tồn tại trong UserNames.txt', () async {
      await service.upsertUserName('鳴人', 'Naruto');

      final removed = await service.removeUserName('佐助');
      expect(removed, isFalse);

      final content = await service.userNamesFile.readAsString();
      expect(content.contains('鳴人=Naruto'), isTrue);
    });

    test('Trả về false khi file chưa tồn tại', () async {
      final removed = await service.removeUserName('佐助');
      expect(removed, isFalse);
    });
  });

  group('UserDictService.removeUserDict', () {
    test('Xóa thành công key đã tồn tại trong UserDict.txt', () async {
      await service.upsertUserDict('こんにちは', 'xin chào');
      await service.upsertUserDict('ありがとう', 'cảm ơn');

      final removed = await service.removeUserDict('こんにちは');
      expect(removed, isTrue);

      final content = await service.userDictFile.readAsString();
      expect(content.contains('こんにちは='), isFalse);
      expect(content.contains('ありがとう=cảm ơn'), isTrue);
    });

    test('Trả về false khi key không tồn tại trong UserDict.txt', () async {
      await service.upsertUserDict('ありがとう', 'cảm ơn');

      final removed = await service.removeUserDict('こんにちは');
      expect(removed, isFalse);
    });
  });
}
