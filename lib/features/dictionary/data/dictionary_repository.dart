import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';
import '../../../core/concurrency.dart';
import '../../dictionary_search/domain/dictionary_search.dart';
import '../../translation/domain/trad2simp_table.dart';
import '../../translation/domain/translation_engine.dart';
import '../../translation/domain/translation_rule.dart';
import '../domain/dict_type.dart';
import '../domain/phrase_dictionary.dart';
import 'dictionary_loader.dart';
import 'japanese_variant_loader.dart';

class LoadedDictionaries {
  final PhraseDictionary userDict;
  final PhraseDictionary names;
  final PhraseDictionary vietPhrase;
  final PhraseDictionary lacViet;
  final PhraseDictionary mazii;
  final PhraseDictionary chinesePhienAm;
  final PhraseDictionary pronouns;
  final PhraseDictionary babylon;
  final PhraseDictionary thieuChuu;
  final PhraseDictionary cedict;
  final PhraseDictionary chinesePhienAmEnglish;
  final PhraseDictionary jaVi;
  final PhraseDictionary zhVi;

  /// Kết quả tra online đã lưu (`OnlineDict_<mode>.txt` trong appdata; rỗng khi
  /// chưa tra lần nào). Value là các mục `<<Nguồn>>` ghép lại, escape `\n`.
  final PhraseDictionary onlineDict;

  /// Đoạn phân tích đầy đủ của các lần tra AI (`AiDict_<mode>.txt`, value là
  /// JSON). CHỈ dùng cho ô Nghĩa — không tham gia dịch.
  final PhraseDictionary aiDict;

  /// Các từ/cụm con AI tách ra khi tra (`AiEntries_<mode>.txt`, `key=nghĩa
  /// ngắn`). Đây là phần AI tham gia greedy match của engine dịch, xếp SAU
  /// VietPhrase nên không bao giờ đè từ điển gốc.
  final PhraseDictionary aiEntries;

  /// Phát âm kana từ SudachiDict (data/jp/SudachiReadings.txt, chỉ mode Nhật;
  /// rỗng khi thiếu file). Dùng làm fallback phát âm trong ô Nghĩa.
  final PhraseDictionary sudachiReadings;
  final TranslationRuleEngine ruleEngine;

  /// Các lớp từ điển chưa merge, theo thứ tự overlay cao → thấp. Search Center
  /// dùng danh sách này để chỉ ra mục nào đang thắng mà không đụng hot path.
  final List<DictionarySearchLayer> searchLayers;

  /// fromCache + thời gian load từng dict (log/hiển thị).
  final Map<DictType, ({bool fromCache, int elapsedMs})> stats;

  LoadedDictionaries({
    required this.userDict,
    required this.names,
    required this.vietPhrase,
    required this.lacViet,
    PhraseDictionary? mazii,
    required this.chinesePhienAm,
    required this.pronouns,
    required this.babylon,
    required this.thieuChuu,
    required this.cedict,
    required this.chinesePhienAmEnglish,
    required this.jaVi,
    required this.zhVi,
    PhraseDictionary? onlineDict,
    PhraseDictionary? aiDict,
    PhraseDictionary? aiEntries,
    PhraseDictionary? sudachiReadings,
    TranslationRuleEngine? ruleEngine,
    this.searchLayers = const [],
    required this.stats,
  }) : mazii = mazii ?? PhraseDictionary(DictType.mazii, const {}),
       onlineDict =
           onlineDict ?? PhraseDictionary(DictType.onlineDict, const {}),
       aiDict =
           aiDict ?? PhraseDictionary(DictType.aiDict, const {}),
       aiEntries =
           aiEntries ?? PhraseDictionary(DictType.aiEntries, const {}),
       sudachiReadings =
           sudachiReadings ?? PhraseDictionary(DictType.jaVi, const {}),
       ruleEngine = ruleEngine ?? const TranslationRuleEngine();

  /// Engine với thứ tự ưu tiên UserDict > Names > VietPhrase.
  TranslationEngine get engine => engineWith();

  /// Engine với tùy chọn thuật toán từ Cài đặt.
  TranslationEngine engineWith({
    TranslationAlgorithm algorithm = TranslationAlgorithm.leftToRight,
    bool prioritizeNames = false,
    PersonRuleScope personRuleScope = PersonRuleScope.off,
  }) => TranslationEngine(
    // aiEntries đứng cuối: chỉ được dùng khi ba từ điển gốc không có mục nào
    // khớp, nên mục AI tự sinh không bao giờ đè bản dịch đã có.
    dicts: [userDict, names, vietPhrase, aiEntries],
    hanVietFallback: chinesePhienAm,
    algorithm: algorithm,
    prioritizeNames: prioritizeNames,
    ruleEngine: ruleEngine,
    personRuleDicts: personRuleDictsFor(personRuleScope),
  );

  List<PhraseDictionary> personRuleDictsFor(PersonRuleScope scope) =>
      switch (scope) {
        PersonRuleScope.off => const [],
        PersonRuleScope.pronouns => [pronouns],
        PersonRuleScope.pronounsAndNames => [pronouns, names],
        PersonRuleScope.pronounsNamesAndVietPhrase => [
          pronouns,
          names,
          vietPhrase,
        ],
      };

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

  String onlineDictPath(TranslationMode mode, {String? inDir}) => p.join(
    inDir ?? paths.dictionariesDir.path,
    'OnlineDict_${mode.name}.txt',
  );

  String aiDictPath(TranslationMode mode, {String? inDir}) =>
      p.join(inDir ?? paths.dictionariesDir.path, 'AiDict_${mode.name}.txt');

  String aiEntriesPath(TranslationMode mode, {String? inDir}) =>
      p.join(inDir ?? paths.dictionariesDir.path, 'AiEntries_${mode.name}.txt');

  String vietPhraseOverlayPath(TranslationMode mode, {String? inDir}) => p.join(
    inDir ?? paths.dictionariesDir.path,
    'VietPhrase_${mode.name}.txt',
  );

  Future<LoadedDictionaries> loadAll(
    Map<DictType, String> dictPaths, {
    required TranslationMode mode,
    bool useSudachiVariants = true,
    Trad2SimpTable? trad2simp,
    String? generatedDir,
  }) async {
    // Bộ dict đã quy giản dùng cache riêng; chữ ký bảng nằm trong tên file nên
    // sinh lại trad2simp.tsv là cache cũ tự bị bỏ qua.
    final cacheVariant = trad2simp == null ? '' : 'simp${trad2simp.signature}';
    Future<LoadResult> loadPath(DictType type, String source) => loadDictionary(
      sourcePath: source,
      cachePath: paths.cacheFileFor(source, variant: cacheVariant),
      type: type,
      trad2simp: trad2simp,
    );

    // File Sudachi sinh bởi tool/build_sudachi_assets.dart, nằm cạnh
    // VietPhrase nguồn (data/jp; data/cn không có → dict rỗng).
    String sudachiPath(String fileName) =>
        p.join(p.dirname(dictPaths[DictType.vietPhrase]!), fileName);

    Future<LoadResult> emptyResult(DictType type) async => LoadResult(
      PhraseDictionary(type, const {}),
      fromCache: false,
      elapsedMs: 0,
    );

    Future<LoadResult> load(DictType type) {
      final source = type == DictType.userDict
          ? userDictPath
          : resolveSourcePath(type, dictPaths[type]!, mode: mode);
      return loadPath(type, source);
    }

    // Dựng index biến thể mất vài giây; chạy song song với các dict để không
    // cộng thẳng vào thời gian mở app.
    final variantIndexFuture =
        mode == TranslationMode.japanese && useSudachiVariants
        ? loadJapaneseVariantIndex(sudachiPath('SudachiVariantGroups.txt'))
        : null;

    // Mobile: 20 isolate cùng lúc = 20 bộ (bytes nguồn + map đã parse) nằm
    // trong RAM một lúc → vượt heap Android. Chạy tối đa 2; desktop giữ nguyên
    // song song hết. Thứ tự kết quả không đổi nên các chỉ số bên dưới vẫn đúng.
    final results = await runWithConcurrency<LoadResult>([
      () => load(DictType.userDict), // 0
      () => load(DictType.names), // 1
      () => load(DictType.vietPhrase), // 2
      () => load(DictType.lacViet), // 3
      () => load(DictType.chinesePhienAm), // 4
      () => load(DictType.pronouns), // 5
      () => load(DictType.babylon), // 6
      () => load(DictType.thieuChuu), // 7
      () => load(DictType.cedict), // 8
      () => load(DictType.chinesePhienAmEnglish), // 9
      () => load(DictType.jaVi), // 10
      () => load(DictType.zhVi), // 11
      () => loadPath(DictType.names, userNamesPath), // 12 (overlay "Thêm vào Names")
      () => loadPath(DictType.vietPhrase, sharedVietPhrasePath(mode)), // 13
      () => loadPath(DictType.lacViet, sharedLacVietPath(mode)), // 14
      () => useSudachiVariants
          ? loadPath(DictType.vietPhrase, sudachiPath('SudachiVariants.txt'))
          : emptyResult(DictType.vietPhrase), // 15
      () => loadPath(DictType.jaVi, sudachiPath('SudachiReadings.txt')), // 16
      () => load(DictType.mazii), // 17
      () => loadPath(DictType.onlineDict, onlineDictPath(mode)), // 18
      () => loadPath(DictType.aiDict, aiDictPath(mode)), // 19
      () => loadPath(DictType.aiEntries, aiEntriesPath(mode)), // 20
      // 21-23: bản dùng chung do admin sinh ra, nằm trong data/<lang>/generated
      // và được đóng gói theo bản phát hành. Không phải admin → generatedDir
      // null → bỏ qua, không tốn isolate đọc file không tồn tại.
      () => generatedDir == null
          ? emptyResult(DictType.onlineDict)
          : loadPath(DictType.onlineDict, onlineDictPath(mode, inDir: generatedDir)), // 21
      () => generatedDir == null
          ? emptyResult(DictType.aiDict)
          : loadPath(DictType.aiDict, aiDictPath(mode, inDir: generatedDir)), // 22
      () => generatedDir == null
          ? emptyResult(DictType.aiEntries)
          : loadPath(DictType.aiEntries, aiEntriesPath(mode, inDir: generatedDir)), // 23
      // 24-25: từ tra được mà VietPhrase gốc chưa có → overlay VietPhrase.
      () => loadPath(DictType.vietPhrase, vietPhraseOverlayPath(mode)), // 24
      () => generatedDir == null
          ? emptyResult(DictType.vietPhrase)
          : loadPath(
              DictType.vietPhrase,
              vietPhraseOverlayPath(mode, inDir: generatedDir),
            ), // 25
    ], limit: Platform.isAndroid || Platform.isIOS ? 2 : 0);

    final hasDynamicOverlays = [
      results[0].dictionary,
      results[12].dictionary,
      results[13].dictionary,
      results[14].dictionary,
    ].any((dictionary) => !dictionary.isEmpty);
    final variantIndex = await variantIndexFuture;
    final dynamicVariantIndex = hasDynamicOverlays ? variantIndex : null;

    PhraseDictionary expandDynamic(PhraseDictionary dictionary) {
      if (dynamicVariantIndex == null || dynamicVariantIndex.isEmpty) {
        return dictionary;
      }
      return PhraseDictionary(
        dictionary.type,
        dynamicVariantIndex.expandEntries(dictionary.entries),
      );
    }

    final personRuleFile = File(
      p.join(p.dirname(dictPaths[DictType.vietPhrase]!), 'LuatNhan.txt'),
    );
    final personRuleSource = await personRuleFile.exists()
        ? await personRuleFile.readAsString()
        : '';
    final personRules = parsePersonRules(personRuleSource);

    // Từ điển sinh khi tra: bản dùng chung (data/<lang>/generated) nằm dưới,
    // mục cá nhân trong userdata đè lên khi trùng key.
    PhraseDictionary mergeGenerated(
      DictType type,
      LoadResult personal,
      LoadResult shared,
    ) {
      if (shared.dictionary.isEmpty) return personal.dictionary;
      if (personal.dictionary.isEmpty) return shared.dictionary;
      return PhraseDictionary(type, {
        ...shared.dictionary.entries,
        ...personal.dictionary.entries,
      });
    }

    final userDict = expandDynamic(results[0].dictionary);
    var names = results[1].dictionary;
    final userNames = expandDynamic(results[12].dictionary);
    if (!userNames.isEmpty) {
      names = PhraseDictionary(DictType.names, {
        ...names.entries,
        ...userNames.entries,
      });
    }

    var vietPhrase = results[2].dictionary;
    final sudachiVariants = results[15].dictionary;
    final sharedVietPhrase = expandDynamic(results[13].dictionary);
    // Từ tra được mà VietPhrase gốc chưa có (bản dùng chung + bản cá nhân).
    final vietPhraseOverlay = expandDynamic(
      mergeGenerated(DictType.vietPhrase, results[24], results[25]),
    );
    if (!sudachiVariants.isEmpty ||
        !sharedVietPhrase.isEmpty ||
        !vietPhraseOverlay.isEmpty) {
      // Biến thể Sudachi merge DƯỚI VietPhrase (key trùng thì VietPhrase
      // thắng); overlay từ tra được nằm trên VietPhrase gốc nhưng dưới Shared.
      vietPhrase = PhraseDictionary(DictType.vietPhrase, {
        ...sudachiVariants.entries,
        ...vietPhrase.entries,
        ...vietPhraseOverlay.entries,
        ...sharedVietPhrase.entries,
      });
    }

    var lacViet = results[3].dictionary;
    final sharedLacViet = expandDynamic(results[14].dictionary);
    if (!sharedLacViet.isEmpty) {
      lacViet = PhraseDictionary(DictType.lacViet, {
        ...lacViet.entries,
        ...sharedLacViet.entries,
      });
    }

    final onlineDict = mergeGenerated(
      DictType.onlineDict,
      results[18],
      results[21],
    );
    final aiDict = mergeGenerated(DictType.aiDict, results[19], results[22]);
    final aiEntries = expandDynamic(
      mergeGenerated(DictType.aiEntries, results[20], results[23]),
    );

    return LoadedDictionaries(
      userDict: userDict,
      names: names,
      vietPhrase: vietPhrase,
      lacViet: lacViet,
      mazii: results[17].dictionary,
      chinesePhienAm: results[4].dictionary,
      pronouns: results[5].dictionary,
      babylon: results[6].dictionary,
      thieuChuu: results[7].dictionary,
      cedict: results[8].dictionary,
      chinesePhienAmEnglish: results[9].dictionary,
      jaVi: results[10].dictionary,
      zhVi: results[11].dictionary,
      onlineDict: onlineDict,
      aiDict: aiDict,
      aiEntries: aiEntries,
      sudachiReadings: results[16].dictionary,
      ruleEngine: TranslationRuleEngine(personRules: personRules.rules),
      searchLayers: [
        DictionarySearchLayer(
          id: 'userDict',
          label: 'UserDict',
          type: DictType.userDict,
          entries: userDict.entries,
        ),
        DictionarySearchLayer(
          id: 'userNames',
          label: 'UserNames (overlay)',
          type: DictType.names,
          entries: userNames.entries,
        ),
        DictionarySearchLayer(
          id: 'names',
          label: 'Names gốc',
          type: DictType.names,
          entries: results[1].dictionary.entries,
        ),
        DictionarySearchLayer(
          id: 'sharedVietPhrase',
          label: 'VietPhrase chung',
          type: DictType.vietPhrase,
          entries: sharedVietPhrase.entries,
        ),
        DictionarySearchLayer(
          id: 'vietPhrase',
          label: 'VietPhrase gốc',
          type: DictType.vietPhrase,
          entries: results[2].dictionary.entries,
        ),
        DictionarySearchLayer(
          id: 'sudachiVariants',
          label: 'Biến thể Sudachi',
          type: DictType.vietPhrase,
          entries: results[15].dictionary.entries,
        ),
        DictionarySearchLayer(
          id: 'sharedLacViet',
          label: 'Lạc Việt chung',
          type: DictType.lacViet,
          entries: sharedLacViet.entries,
        ),
        DictionarySearchLayer(
          id: 'lacViet',
          label: 'Lạc Việt gốc',
          type: DictType.lacViet,
          entries: results[3].dictionary.entries,
        ),
        for (final item in <(String, String, int)>[
          ('mazii', 'Mazii offline', 17),
          ('chinesePhienAm', 'Phiên âm Hán Việt', 4),
          ('pronouns', 'Đại từ', 5),
          ('babylon', 'Babylon', 6),
          ('thieuChuu', 'Thiều Chửu', 7),
          ('cedict', 'CEDICT', 8),
          ('chinesePhienAmEnglish', 'Phiên âm Anh', 9),
          ('jaVi', 'Nhật Việt', 10),
          ('zhVi', 'Trung Việt', 11),
        ])
          DictionarySearchLayer(
            id: item.$1,
            label: item.$2,
            type: results[item.$3].dictionary.type,
            entries: results[item.$3].dictionary.entries,
          ),
        // Đã merge bản chung + cá nhân nên hiện thẳng bộ đã gộp.
        DictionarySearchLayer(
          id: 'onlineDict',
          label: 'Online đã lưu',
          type: DictType.onlineDict,
          entries: onlineDict.entries,
        ),
        DictionarySearchLayer(
          id: 'aiDict',
          label: 'AI đã lưu',
          type: DictType.aiDict,
          entries: aiDict.entries,
        ),
        DictionarySearchLayer(
          id: 'aiEntries',
          label: 'AI tách từ',
          type: DictType.aiEntries,
          entries: aiEntries.entries,
        ),
      ],
      stats: {
        for (final r in results.take(12))
          r.dictionary.type: (fromCache: r.fromCache, elapsedMs: r.elapsedMs),
        DictType.mazii: (
          fromCache: results[17].fromCache,
          elapsedMs: results[17].elapsedMs,
        ),
        DictType.onlineDict: (
          fromCache: results[18].fromCache,
          elapsedMs: results[18].elapsedMs,
        ),
        DictType.aiEntries: (
          fromCache: results[20].fromCache,
          elapsedMs: results[20].elapsedMs,
        ),
        DictType.aiDict: (
          fromCache: results[19].fromCache,
          elapsedMs: results[19].elapsedMs,
        ),
      },
    );
  }
}
