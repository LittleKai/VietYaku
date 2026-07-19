import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/translation/domain/translation_engine.dart';
import '../dictionary/domain/dict_type.dart';
import '../repair/domain/jp_repair_pipeline.dart';

/// Bộ từ điển bundle trong dự án (data/jp, data/cn), đổi được trong Cài đặt.
///
/// Desktop: trỏ vào checkout dự án. Mobile (Android): được gán lại =
/// `<appSupport>/data` sau khi seed từ assets trong `main()` (đường dẫn tuyệt
/// đối của dev không tồn tại trên máy Android). Là biến (không `const`) để
/// `main()` ghi đè trước khi `SettingsNotifier.build()` đọc.
String defaultDataDir = r'D:\Dev\Python\LittleKai_Ecosystem\VietYaku\data';
const defaultSyncServerUrl = String.fromEnvironment(
  'LITTLEKAI_SERVER_URL',
  defaultValue: 'http://localhost:5000',
);

String _loadSyncServerUrlFromEnv() {
  try {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    var envFile = File(p.join(exeDir, '.env'));
    if (!envFile.existsSync()) {
      envFile = File(p.join(Directory.current.path, '.env'));
    }
    if (envFile.existsSync()) {
      final lines = envFile.readAsLinesSync();
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split('=');
        if (parts.length >= 2 && parts[0].trim() == 'LITTLEKAI_SERVER_URL') {
          var val = parts.sublist(1).join('=').trim();
          if ((val.startsWith('"') && val.endsWith('"')) ||
              (val.startsWith("'") && val.endsWith("'"))) {
            val = val.substring(1, val.length - 1);
          }
          if (val.isNotEmpty) {
            return val.replaceFirst(RegExp(r'/+$'), '');
          }
        }
      }
    }
  } catch (_) {}
  return defaultSyncServerUrl;
}

const modeDirNames = <TranslationMode, String>{
  TranslationMode.japanese: 'jp',
  TranslationMode.chinese: 'cn',
};

const dictFileNames = <DictType, String>{
  DictType.vietPhrase: 'VietPhrase.txt',
  DictType.lacViet: 'LacViet.txt',
  DictType.names: 'Names.txt',
  DictType.chinesePhienAm: 'ChinesePhienAmWords.txt',
  DictType.pronouns: 'Pronouns.txt',
  DictType.babylon: 'Babylon.txt',
  DictType.thieuChuu: 'ThieuChuu.txt',
  DictType.cedict: 'cedict_ts.u8',
  DictType.chinesePhienAmEnglish: 'ChinesePhienAmEnglishWords.txt',
  DictType.jaVi: 'JaViDict.txt',
  DictType.zhVi: 'ZhViDict.txt',
};

/// Các ô có cỡ chữ + font chỉnh riêng biệt nhau.
enum PaneId { source, hanViet, vietPhrase, meaning, viet }

const paneLabels = <PaneId, String>{
  PaneId.source: 'Nguồn',
  PaneId.hanViet: 'Hán Việt',
  PaneId.vietPhrase: 'VietPhrase',
  PaneId.meaning: 'Nghĩa',
  PaneId.viet: 'Ô Việt',
};

/// Cỡ chữ + font của một ô ('' = font hệ thống).
class PaneFont {
  final double size;
  final String family;

  const PaneFont({this.size = 14, this.family = ''});

  TextStyle style({double height = 1.5}) => TextStyle(
    fontSize: size,
    fontFamily: family.isEmpty ? null : family,
    height: height,
  );

  PaneFont copyWith({double? size, String? family}) =>
      PaneFont(size: size ?? this.size, family: family ?? this.family);
}

class AppSettings {
  /// Đường dẫn file dict nguồn theo ngôn ngữ (JP/CN mỗi bộ riêng).
  final Map<TranslationMode, Map<DictType, String>> dictPaths;
  final TranslationMode defaultMode;
  final TranslationAlgorithm translationAlgorithm;

  /// Names thắng cụm VietPhrase dài hơn tại cùng vị trí (UserDict vẫn cao nhất).
  final bool prioritizeNames;

  /// Mode Nhật: gộp run số kanji không match thành số Ả Rập (三百二十五 → 325).
  final bool joinKanjiNumerals;

  /// Mode Nhật: chuẩn hoá halfwidth katakana (ｱｲｳ → アイウ) trước khi tra.
  final bool normalizeHalfwidthKana;

  /// Mode Nhật: merge từ điển biến thể Sudachi (data/jp/SudachiVariants.txt)
  /// dưới VietPhrase. Đổi setting → nạp lại bộ từ điển.
  final bool sudachiVariants;

  /// Mode Nhật: fallback phát âm kana từ data/jp/SudachiReadings.txt
  /// trong ô Nghĩa khi Nhật Việt/Lạc Việt không có.
  final bool sudachiReadings;

  /// Chính sách repair Key thuần Hán (màn Sửa từ điển) — chỉnh ở Cài đặt.
  final RepairPolicy repairPolicy;

  /// Cỡ chữ + font riêng cho từng ô.
  final Map<PaneId, PaneFont> paneFonts;
  final String syncServerUrl;
  final bool isSyncServerUrlOverridden;

  /// Tỷ lệ bố cục 4 ô (lưu để khôi phục khi mở lại):
  /// - [columnsRatio]: bề rộng cột trái / tổng.
  /// - [leftSplitRatio]: chiều cao ô Nguồn / cột trái.
  /// - [rightSplitRatio]: chiều cao ô VietPhrase / cột phải.
  final double columnsRatio;
  final double leftSplitRatio;
  final double rightSplitRatio;

  /// Màu chữ katakana/furigana (kana không match) trong ô VietPhrase (ARGB).
  final int katakanaColor;

  /// Tab đa nghĩa: bọc `[ ]` cả cụm có trong từ điển mà chỉ có 1 nghĩa.
  final bool bracketSingleMeaning;

  /// Giữ nguyên ngoặc kép CJK đặc biệt 『』《》〈〉〝〞〟 khi hiển thị
  /// (false → chuyển thành `"`). 「」 luôn chuyển thành `"`.
  final bool keepSpecialQuotes;

  /// Voice TTS đã chọn theo ngôn ngữ (`"name::locale"`; '' = tự động chọn).
  final String ttsVoiceJa;
  final String ttsVoiceZh;

  /// Tốc độ đọc TTS (0.1–1.0).
  final double ttsSpeechRate;

  const AppSettings({
    required this.dictPaths,
    required this.defaultMode,
    this.translationAlgorithm = TranslationAlgorithm.leftToRight,
    this.prioritizeNames = false,
    this.joinKanjiNumerals = true,
    this.normalizeHalfwidthKana = true,
    this.sudachiVariants = true,
    this.sudachiReadings = true,
    this.repairPolicy = RepairPolicy.addVariant,
    this.paneFonts = const {},
    this.syncServerUrl = defaultSyncServerUrl,
    this.isSyncServerUrlOverridden = false,
    this.columnsRatio = 0.42,
    this.leftSplitRatio = 0.6,
    this.rightSplitRatio = 0.6,
    this.katakanaColor = 0xFF2E7D32,
    this.bracketSingleMeaning = true,
    this.keepSpecialQuotes = true,
    this.ttsVoiceJa = '',
    this.ttsVoiceZh = '',
    this.ttsSpeechRate = 0.5,
  });

  /// Voice đã chọn cho [mode] ('' = tự động).
  String ttsVoiceFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? ttsVoiceJa : ttsVoiceZh;

  PaneFont paneFontFor(PaneId id) => paneFonts[id] ?? const PaneFont();

  /// Style chữ áp cho nội dung của ô [id].
  TextStyle paneTextStyleFor(PaneId id, {double height = 1.5}) =>
      paneFontFor(id).style(height: height);

  Map<DictType, String> dictPathsFor(TranslationMode mode) => dictPaths[mode]!;

  AppSettings copyWith({
    Map<TranslationMode, Map<DictType, String>>? dictPaths,
    TranslationMode? defaultMode,
    TranslationAlgorithm? translationAlgorithm,
    bool? prioritizeNames,
    bool? joinKanjiNumerals,
    bool? normalizeHalfwidthKana,
    bool? sudachiVariants,
    bool? sudachiReadings,
    RepairPolicy? repairPolicy,
    Map<PaneId, PaneFont>? paneFonts,
    String? syncServerUrl,
    bool? isSyncServerUrlOverridden,
    double? columnsRatio,
    double? leftSplitRatio,
    double? rightSplitRatio,
    int? katakanaColor,
    bool? bracketSingleMeaning,
    bool? keepSpecialQuotes,
    String? ttsVoiceJa,
    String? ttsVoiceZh,
    double? ttsSpeechRate,
  }) => AppSettings(
    dictPaths: dictPaths ?? this.dictPaths,
    defaultMode: defaultMode ?? this.defaultMode,
    translationAlgorithm: translationAlgorithm ?? this.translationAlgorithm,
    prioritizeNames: prioritizeNames ?? this.prioritizeNames,
    joinKanjiNumerals: joinKanjiNumerals ?? this.joinKanjiNumerals,
    normalizeHalfwidthKana:
        normalizeHalfwidthKana ?? this.normalizeHalfwidthKana,
    sudachiVariants: sudachiVariants ?? this.sudachiVariants,
    sudachiReadings: sudachiReadings ?? this.sudachiReadings,
    repairPolicy: repairPolicy ?? this.repairPolicy,
    paneFonts: paneFonts ?? this.paneFonts,
    syncServerUrl: syncServerUrl ?? this.syncServerUrl,
    isSyncServerUrlOverridden: isSyncServerUrlOverridden ?? this.isSyncServerUrlOverridden,
    columnsRatio: columnsRatio ?? this.columnsRatio,
    leftSplitRatio: leftSplitRatio ?? this.leftSplitRatio,
    rightSplitRatio: rightSplitRatio ?? this.rightSplitRatio,
    katakanaColor: katakanaColor ?? this.katakanaColor,
    bracketSingleMeaning: bracketSingleMeaning ?? this.bracketSingleMeaning,
    keepSpecialQuotes: keepSpecialQuotes ?? this.keepSpecialQuotes,
    ttsVoiceJa: ttsVoiceJa ?? this.ttsVoiceJa,
    ttsVoiceZh: ttsVoiceZh ?? this.ttsVoiceZh,
    ttsSpeechRate: ttsSpeechRate ?? this.ttsSpeechRate,
  );

  static AppSettings defaults() => AppSettings(
    dictPaths: {
      for (final mode in TranslationMode.values)
        mode: {
          for (final entry in dictFileNames.entries)
            entry.key: p.join(defaultDataDir, modeDirNames[mode]!, entry.value),
        },
    },
    defaultMode: TranslationMode.japanese,
  );
}

/// Override trong main() sau khi có SharedPreferences.getInstance().
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

class SettingsNotifier extends Notifier<AppSettings> {
  static String _pathKey(TranslationMode mode, DictType type) =>
      'dictPath.${mode.name}.${type.name}';
  static const _modeKey = 'defaultMode';
  static const _algorithmKey = 'translationAlgorithm';
  static const _prioritizeNamesKey = 'prioritizeNames';
  static const _joinKanjiNumeralsKey = 'translate.joinKanjiNumerals';
  static const _normalizeHalfwidthKanaKey = 'translate.normalizeHalfwidthKana';
  static const _sudachiVariantsKey = 'translate.sudachiVariants';
  static const _sudachiReadingsKey = 'translate.sudachiReadings';
  static const _repairPolicyKey = 'repairPolicy';
  static const _syncServerUrlKey = 'syncServerUrl';
  static const _columnsRatioKey = 'layout.columnsRatio';
  static const _leftSplitRatioKey = 'layout.leftSplitRatio';
  static const _rightSplitRatioKey = 'layout.rightSplitRatio';
  static const _katakanaColorKey = 'katakanaColor';
  static const _bracketSingleMeaningKey = 'display.bracketSingle';
  static const _keepSpecialQuotesKey = 'display.keepSpecialQuotes';
  static const _ttsVoiceJaKey = 'tts.voice.ja';
  static const _ttsVoiceZhKey = 'tts.voice.zh';
  static const _ttsSpeechRateKey = 'tts.speechRate';
  static String _fontSizeKey(PaneId id) => 'paneFont.${id.name}.size';
  static String _fontFamilyKey(PaneId id) => 'paneFont.${id.name}.family';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final defaults = AppSettings.defaults();
    final envUrl = _loadSyncServerUrlFromEnv();
    final isOverridden = envUrl != defaultSyncServerUrl;
    return AppSettings(
      dictPaths: {
        for (final modeEntry in defaults.dictPaths.entries)
          modeEntry.key: {
            for (final entry in modeEntry.value.entries)
              entry.key:
                  prefs.getString(_pathKey(modeEntry.key, entry.key)) ??
                  entry.value,
          },
      },
      defaultMode: prefs.getString(_modeKey) == TranslationMode.chinese.name
          ? TranslationMode.chinese
          : TranslationMode.japanese,
      translationAlgorithm:
          TranslationAlgorithm.values.asNameMap()[prefs.getString(
            _algorithmKey,
          )] ??
          TranslationAlgorithm.leftToRight,
      prioritizeNames: prefs.getBool(_prioritizeNamesKey) ?? false,
      joinKanjiNumerals: prefs.getBool(_joinKanjiNumeralsKey) ?? true,
      normalizeHalfwidthKana:
          prefs.getBool(_normalizeHalfwidthKanaKey) ?? true,
      sudachiVariants: prefs.getBool(_sudachiVariantsKey) ?? true,
      sudachiReadings: prefs.getBool(_sudachiReadingsKey) ?? true,
      repairPolicy:
          RepairPolicy.values.asNameMap()[prefs.getString(_repairPolicyKey)] ??
          RepairPolicy.addVariant,
      paneFonts: {
        for (final id in PaneId.values)
          id: PaneFont(
            size: prefs.getDouble(_fontSizeKey(id)) ?? 14,
            family: prefs.getString(_fontFamilyKey(id)) ?? '',
          ),
      },
      syncServerUrl: isOverridden ? envUrl : (prefs.getString(_syncServerUrlKey) ?? defaultSyncServerUrl),
      isSyncServerUrlOverridden: isOverridden,
      columnsRatio: prefs.getDouble(_columnsRatioKey) ?? 0.42,
      leftSplitRatio: prefs.getDouble(_leftSplitRatioKey) ?? 0.6,
      rightSplitRatio: prefs.getDouble(_rightSplitRatioKey) ?? 0.6,
      katakanaColor: prefs.getInt(_katakanaColorKey) ?? 0xFF2E7D32,
      bracketSingleMeaning: prefs.getBool(_bracketSingleMeaningKey) ?? true,
      keepSpecialQuotes: prefs.getBool(_keepSpecialQuotesKey) ?? true,
      ttsVoiceJa: prefs.getString(_ttsVoiceJaKey) ?? '',
      ttsVoiceZh: prefs.getString(_ttsVoiceZhKey) ?? '',
      ttsSpeechRate: prefs.getDouble(_ttsSpeechRateKey) ?? 0.5,
    );
  }

  Future<void> setTtsVoice(TranslationMode mode, String voiceKey) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == TranslationMode.japanese) {
      await prefs.setString(_ttsVoiceJaKey, voiceKey);
      state = state.copyWith(ttsVoiceJa: voiceKey);
    } else {
      await prefs.setString(_ttsVoiceZhKey, voiceKey);
      state = state.copyWith(ttsVoiceZh: voiceKey);
    }
  }

  Future<void> setTtsSpeechRate(double value) async {
    final v = value.clamp(0.1, 1.0);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_ttsSpeechRateKey, v);
    state = state.copyWith(ttsSpeechRate: v);
  }

  Future<void> setKatakanaColor(int color) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_katakanaColorKey, color);
    state = state.copyWith(katakanaColor: color);
  }

  Future<void> setBracketSingleMeaning(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_bracketSingleMeaningKey, value);
    state = state.copyWith(bracketSingleMeaning: value);
  }

  Future<void> setKeepSpecialQuotes(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_keepSpecialQuotesKey, value);
    state = state.copyWith(keepSpecialQuotes: value);
  }

  /// Lưu tỷ lệ bố cục (gọi khi thả thanh kéo). [which]: 'columns'|'left'|'right'.
  Future<void> setLayoutRatio(String which, double value) async {
    final v = value.clamp(0.15, 0.85);
    final prefs = ref.read(sharedPreferencesProvider);
    switch (which) {
      case 'columns':
        await prefs.setDouble(_columnsRatioKey, v);
        state = state.copyWith(columnsRatio: v);
      case 'left':
        await prefs.setDouble(_leftSplitRatioKey, v);
        state = state.copyWith(leftSplitRatio: v);
      case 'right':
        await prefs.setDouble(_rightSplitRatioKey, v);
        state = state.copyWith(rightSplitRatio: v);
    }
  }

  Future<void> setDictPath(
    TranslationMode mode,
    DictType type,
    String path,
  ) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_pathKey(mode, type), path);
    state = state.copyWith(
      dictPaths: {
        ...state.dictPaths,
        mode: {...state.dictPaths[mode]!, type: path},
      },
    );
  }

  Future<void> setDefaultMode(TranslationMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_modeKey, mode.name);
    state = state.copyWith(defaultMode: mode);
  }

  Future<void> setTranslationAlgorithm(TranslationAlgorithm algorithm) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_algorithmKey, algorithm.name);
    state = state.copyWith(translationAlgorithm: algorithm);
  }

  Future<void> setPrioritizeNames(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_prioritizeNamesKey, value);
    state = state.copyWith(prioritizeNames: value);
  }

  Future<void> setJoinKanjiNumerals(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_joinKanjiNumeralsKey, value);
    state = state.copyWith(joinKanjiNumerals: value);
  }

  Future<void> setNormalizeHalfwidthKana(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_normalizeHalfwidthKanaKey, value);
    state = state.copyWith(normalizeHalfwidthKana: value);
  }

  Future<void> setSudachiVariants(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_sudachiVariantsKey, value);
    state = state.copyWith(sudachiVariants: value);
  }

  Future<void> setSudachiReadings(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_sudachiReadingsKey, value);
    state = state.copyWith(sudachiReadings: value);
  }

  Future<void> setRepairPolicy(RepairPolicy policy) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_repairPolicyKey, policy.name);
    state = state.copyWith(repairPolicy: policy);
  }

  Future<void> setPaneFont(PaneId id, {double? size, String? family}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (size != null) await prefs.setDouble(_fontSizeKey(id), size);
    if (family != null) await prefs.setString(_fontFamilyKey(id), family);
    state = state.copyWith(
      paneFonts: {
        ...state.paneFonts,
        id: state.paneFontFor(id).copyWith(size: size, family: family),
      },
    );
  }

  Future<void> setSyncServerUrl(String value) async {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_syncServerUrlKey, normalized);
    state = state.copyWith(syncServerUrl: normalized);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
