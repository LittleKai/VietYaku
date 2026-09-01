import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  late Directory temp;
  late Directory dataDir;
  late AppPaths paths;
  late Map<DictType, String> dictPaths;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('vietyaku_jp_variants_');
    dataDir = Directory(p.join(temp.path, 'data'))..createSync(recursive: true);
    paths = AppPaths(Directory(p.join(temp.path, 'support')));
    paths.cacheDir.createSync(recursive: true);
    paths.dictionariesDir.createSync(recursive: true);

    const names = <DictType, String>{
      DictType.names: 'Names.txt',
      DictType.vietPhrase: 'VietPhrase.txt',
      DictType.lacViet: 'LacViet.txt',
      DictType.mazii: 'Mazii.txt',
      DictType.chinesePhienAm: 'ChinesePhienAmWords.txt',
      DictType.pronouns: 'Pronouns.txt',
      DictType.babylon: 'Babylon.txt',
      DictType.thieuChuu: 'ThieuChuu.txt',
      DictType.cedict: 'cedict_ts.u8',
      DictType.chinesePhienAmEnglish: 'ChinesePhienAmEnglishWords.txt',
      DictType.jaVi: 'JaViDict.txt',
      DictType.zhVi: 'ZhViDict.txt',
    };
    dictPaths = {
      for (final entry in names.entries)
        entry.key: (File(
          p.join(dataDir.path, entry.value),
        )..writeAsStringSync('')).path,
    };

    File(p.join(dataDir.path, 'SudachiVariants.txt')).writeAsStringSync('');
    File(p.join(dataDir.path, 'SudachiReadings.txt')).writeAsStringSync('');
    File(p.join(dataDir.path, 'SudachiVariantGroups.txt')).writeAsStringSync(
      '\uFEFFあつかい\t扱い\r\n'
      'きれ\t切れ\r\n'
      'のみこま\t吞みこま\t吞み込ま\r\n',
    );
    File(
      p.join(paths.dictionariesDir.path, 'UserDict.txt'),
    ).writeAsStringSync('\uFEFF扱い切れ=xử lý được\r\n');
    File(
      p.join(paths.dictionariesDir.path, 'SharedVietPhrase_japanese.txt'),
    ).writeAsStringSync('\uFEFF吞み込ま=nuốt chửng\r\n');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test(
    'mode Nhật mở rộng alias động cho UserDict và shared VietPhrase',
    () async {
      final loaded = await DictionaryRepository(
        paths,
      ).loadAll(dictPaths, mode: TranslationMode.japanese);

      expect(loaded.userDict.entries['扱いきれ'], 'xử lý được');
      expect(loaded.userDict.entries['あつかいきれ'], 'xử lý được');
      expect(loaded.vietPhrase.entries['吞みこま'], 'nuốt chửng');
      expect(loaded.vietPhrase.entries['のみこま'], 'nuốt chửng');

      final tokens = loaded.engine.translate('のみこまれ');
      expect(tokens.first.source, 'のみこま');
      expect(tokens.first.rawValue, 'nuốt chửng');
      expect(tokens.last.source, 'れ');
    },
  );

  test('tắt SudachiVariants thì không sinh alias động', () async {
    final loaded = await DictionaryRepository(paths).loadAll(
      dictPaths,
      mode: TranslationMode.japanese,
      useSudachiVariants: false,
    );

    expect(loaded.userDict.entries['扱いきれ'], isNull);
    expect(loaded.vietPhrase.entries['のみこま'], isNull);
  });

  test('entry dạng thân từ cũng sinh alias', () async {
    // Người dùng hay lưu gốc động từ (`吞み込`) chứ không phải thể chia đầy đủ.
    File(
      p.join(paths.dictionariesDir.path, 'SharedVietPhrase_japanese.txt'),
    ).writeAsStringSync('﻿吞み込=nuốt chửng\r\n');

    final loaded = await DictionaryRepository(
      paths,
    ).loadAll(dictPaths, mode: TranslationMode.japanese);

    expect(loaded.vietPhrase.entries['吞みこ'], 'nuốt chửng');

    final tokens = loaded.engine.translate('吞みこまれ');
    expect(tokens.first.source, '吞みこ');
    expect(tokens.first.rawValue, 'nuốt chửng');
  });

  test('mode Trung không áp dụng nhóm biến thể tiếng Nhật', () async {
    final loaded = await DictionaryRepository(
      paths,
    ).loadAll(dictPaths, mode: TranslationMode.chinese);

    expect(loaded.userDict.entries['扱いきれ'], isNull);
    expect(loaded.vietPhrase.entries['のみこま'], isNull);
  });

  test('thiếu asset nhóm biến thể vẫn nạp overlay như cũ', () async {
    File(p.join(dataDir.path, 'SudachiVariantGroups.txt')).deleteSync();

    final loaded = await DictionaryRepository(
      paths,
    ).loadAll(dictPaths, mode: TranslationMode.japanese);

    expect(loaded.userDict.entries['扱い切れ'], 'xử lý được');
    expect(loaded.userDict.entries['扱いきれ'], isNull);
    expect(loaded.vietPhrase.entries['吞み込ま'], 'nuốt chửng');
    expect(loaded.vietPhrase.entries['のみこま'], isNull);
  });
}
