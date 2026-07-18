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
  final PhraseDictionary babylon;
  final PhraseDictionary thieuChuu;
  final PhraseDictionary cedict;
  final PhraseDictionary chinesePhienAmEnglish;
  final PhraseDictionary jaVi;
  final PhraseDictionary zhVi;

  /// fromCache + thời gian load từng dict (log/hiển thị).
  final Map<DictType, ({bool fromCache, int elapsedMs})> stats;

  LoadedDictionaries({
    required this.userDict,
    required this.names,
    required this.vietPhrase,
    required this.lacViet,
    required this.chinesePhienAm,
    required this.pronouns,
    required this.babylon,
    required this.thieuChuu,
    required this.cedict,
    required this.chinesePhienAmEnglish,
    required this.jaVi,
    required this.zhVi,
    required this.stats,
  });

  /// Engine với thứ tự ưu tiên UserDict > Names > VietPhrase.
  TranslationEngine get engine => engineWith();

  /// Engine với tùy chọn thuật toán từ Cài đặt.
  TranslationEngine engineWith({
    TranslationAlgorithm algorithm = TranslationAlgorithm.leftToRight,
    bool prioritizeNames = false,
  }) => TranslationEngine(
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
  /// Chỉ áp dụng cho mode Nhật — bộ CN dùng thẳng file cấu hình.
  String resolveSourcePath(
    DictType type,
    String configuredPath, {
    required TranslationMode mode,
  }) {
    if (mode != TranslationMode.japanese) return configuredPath;
    final base = p.basenameWithoutExtension(configuredPath);
    final repaired = p.join(paths.dictionariesDir.path, '${base}_JP.txt');
    if (File(repaired).existsSync()) return repaired;
    return configuredPath;
  }

  String get userDictPath => p.join(paths.dictionariesDir.path, 'UserDict.txt');

  String get userNamesPath =>
      p.join(paths.dictionariesDir.path, 'UserNames.txt');

  String sharedVietPhrasePath(TranslationMode mode) =>
      p.join(paths.dictionariesDir.path, 'SharedVietPhrase_${mode.name}.txt');

  String sharedLacVietPath(TranslationMode mode) =>
      p.join(paths.dictionariesDir.path, 'SharedLacViet_${mode.name}.txt');

  Future<LoadedDictionaries> loadAll(
    Map<DictType, String> dictPaths, {
    required TranslationMode mode,
  }) async {
    Future<LoadResult> loadPath(DictType type, String source) => loadDictionary(
      sourcePath: source,
      cachePath: paths.cacheFileFor(source),
      type: type,
    );

    Future<LoadResult> load(DictType type) {
      final source = type == DictType.userDict
          ? userDictPath
          : resolveSourcePath(type, dictPaths[type]!, mode: mode);
      return loadPath(type, source);
    }

    final results = await Future.wait([
      load(DictType.userDict),
      load(DictType.names),
      load(DictType.vietPhrase),
      load(DictType.lacViet),
      load(DictType.chinesePhienAm),
      load(DictType.pronouns),
      load(DictType.babylon),
      load(DictType.thieuChuu),
      load(DictType.cedict),
      load(DictType.chinesePhienAmEnglish),
      load(DictType.jaVi),
      load(DictType.zhVi),
      loadPath(DictType.names, userNamesPath), // overlay "Thêm vào Names"
      loadPath(DictType.vietPhrase, sharedVietPhrasePath(mode)),
      loadPath(DictType.lacViet, sharedLacVietPath(mode)),
    ]);

    var names = results[1].dictionary;
    final userNames = results[12].dictionary;
    if (!userNames.isEmpty) {
      names = PhraseDictionary(DictType.names, {
        ...names.entries,
        ...userNames.entries,
      });
    }

    var vietPhrase = results[2].dictionary;
    final sharedVietPhrase = results[13].dictionary;
    if (!sharedVietPhrase.isEmpty) {
      vietPhrase = PhraseDictionary(DictType.vietPhrase, {
        ...vietPhrase.entries,
        ...sharedVietPhrase.entries,
      });
    }

    var lacViet = results[3].dictionary;
    final sharedLacViet = results[14].dictionary;
    if (!sharedLacViet.isEmpty) {
      lacViet = PhraseDictionary(DictType.lacViet, {
        ...lacViet.entries,
        ...sharedLacViet.entries,
      });
    }

    return LoadedDictionaries(
      userDict: results[0].dictionary,
      names: names,
      vietPhrase: vietPhrase,
      lacViet: lacViet,
      chinesePhienAm: results[4].dictionary,
      pronouns: results[5].dictionary,
      babylon: results[6].dictionary,
      thieuChuu: results[7].dictionary,
      cedict: results[8].dictionary,
      chinesePhienAmEnglish: results[9].dictionary,
      jaVi: results[10].dictionary,
      zhVi: results[11].dictionary,
      stats: {
        for (final r in results.take(12))
          r.dictionary.type: (fromCache: r.fromCache, elapsedMs: r.elapsedMs),
      },
    );
  }
}
