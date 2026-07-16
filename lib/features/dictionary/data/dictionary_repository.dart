import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';
import '../../translation/domain/translation_engine.dart';
import '../domain/dict_type.dart';
import '../domain/phrase_dictionary.dart';
import 'dictionary_loader.dart';

class LoadedDictionaries {
  final PhraseDictionary userDict;
  final PhraseDictionary names;
  final PhraseDictionary vietPhrase;
  final PhraseDictionary lacViet;
  final PhraseDictionary chinesePhienAm;
  final PhraseDictionary pronouns;

  /// fromCache + thời gian load từng dict (log/hiển thị).
  final Map<DictType, ({bool fromCache, int elapsedMs})> stats;

  LoadedDictionaries({
    required this.userDict,
    required this.names,
    required this.vietPhrase,
    required this.lacViet,
    required this.chinesePhienAm,
    required this.pronouns,
    required this.stats,
  });

  /// Engine với thứ tự ưu tiên UserDict > Names > VietPhrase.
  TranslationEngine get engine => engineWith();

  /// Engine với tùy chọn thuật toán từ Cài đặt.
  TranslationEngine engineWith({
    TranslationAlgorithm algorithm = TranslationAlgorithm.leftToRight,
    bool prioritizeNames = false,
  }) =>
      TranslationEngine(
        dicts: [userDict, names, vietPhrase],
        hanVietFallback: chinesePhienAm,
        algorithm: algorithm,
        prioritizeNames: prioritizeNames,
      );

  /// Engine phiên âm Hán Việt toàn văn (tab Hán Việt).
  TranslationEngine get hanVietEngine =>
      TranslationEngine(dicts: const [], hanVietFallback: chinesePhienAm);
}

class DictionaryRepository {
  final AppPaths paths;

  DictionaryRepository(this.paths);

  /// File đã sửa trong appdata (`<tên>_JP.txt`) được ưu tiên hơn file nguồn.
  String resolveSourcePath(DictType type, String configuredPath) {
    final base = p.basenameWithoutExtension(configuredPath);
    final repaired = p.join(paths.dictionariesDir.path, '${base}_JP.txt');
    if (File(repaired).existsSync()) return repaired;
    return configuredPath;
  }

  String get userDictPath => p.join(paths.dictionariesDir.path, 'UserDict.txt');

  String get userNamesPath =>
      p.join(paths.dictionariesDir.path, 'UserNames.txt');

  Future<LoadedDictionaries> loadAll(Map<DictType, String> dictPaths) async {
    Future<LoadResult> loadPath(DictType type, String source) =>
        loadDictionary(
          sourcePath: source,
          cachePath: paths.cacheFileFor(source),
          type: type,
        );

    Future<LoadResult> load(DictType type) {
      final source = type == DictType.userDict
          ? userDictPath
          : resolveSourcePath(type, dictPaths[type]!);
      return loadPath(type, source);
    }

    final results = await Future.wait([
      load(DictType.userDict),
      load(DictType.names),
      load(DictType.vietPhrase),
      load(DictType.lacViet),
      load(DictType.chinesePhienAm),
      load(DictType.pronouns),
      loadPath(DictType.names, userNamesPath), // overlay "Thêm vào Names"
    ]);

    // UserNames overlay đè lên Names gốc (không đụng file gốc).
    var names = results[1].dictionary;
    final userNames = results[6].dictionary;
    if (!userNames.isEmpty) {
      names = PhraseDictionary(
          DictType.names, {...names.entries, ...userNames.entries});
    }

    return LoadedDictionaries(
      userDict: results[0].dictionary,
      names: names,
      vietPhrase: results[2].dictionary,
      lacViet: results[3].dictionary,
      chinesePhienAm: results[4].dictionary,
      pronouns: results[5].dictionary,
      stats: {
        for (final r in results.take(6))
          r.dictionary.type: (fromCache: r.fromCache, elapsedMs: r.elapsedMs),
      },
    );
  }
}
