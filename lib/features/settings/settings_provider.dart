import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/translation/domain/translation_engine.dart';
import '../translation/domain/lookup_dictionary_type.dart';
import '../translation/domain/meaning_panel_layout.dart';
import '../translation/domain/online_lookup_source.dart';
import '../translation/domain/translation_rule.dart';
import '../translation/domain/vietphrase_value.dart';
import '../dictionary/domain/dict_type.dart';
import '../dictionary_sync/domain/sync_reminder.dart';
import '../repair/domain/jp_repair_pipeline.dart';

/// Bộ từ điển bundle trong dự án (data/jp, data/cn), đổi được trong Cài đặt.
///
/// Desktop: trỏ vào checkout dự án. Mobile (Android): được gán lại =
/// `<appSupport>/data` sau khi seed từ assets trong `main()` (đường dẫn tuyệt
/// đối của dev không tồn tại trên máy Android). Là biến (không `const`) để
/// `main()` ghi đè trước khi `SettingsNotifier.build()` đọc.
String defaultDataDir = r'D:\Dev\Python\LittleKai_Ecosystem\VietYaku\data';

/// Thư mục `Glossary/` của AI_Translation_Bridge (chứa `JP/` và `CN/`).
const defaultGlossaryDir =
    r'D:\Dev\Python\LittleKai_Ecosystem\AI_Translation_Bridge\Glossary';
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

/// Thư mục con của bộ dict chứa từ điển do app sinh ra khi tra (AI/online).
///
/// Chỉ phiên admin mới ghi vào đây: nằm trong `data/<lang>` nên được đóng gói
/// theo bản phát hành, tách khỏi từ điển nguồn nhờ thư mục con riêng. Người
/// dùng thường vẫn ghi vào `userdata/dictionaries` — app nạp cả hai và mục cá
/// nhân đè lên mục dùng chung.
///
/// An toàn khi cập nhật app: self-update Windows dùng `xcopy /E /Y` (ghi đè,
/// không xoá file thừa) và `seedLanguagePack` trên mobile cũng chép đè chứ
/// không dọn thư mục, nên thư mục con này sống sót qua các bản cập nhật.
String generatedDictDir(TranslationMode mode) =>
    p.join(defaultDataDir, modeDirNames[mode]!, 'generated');

const dictFileNames = <DictType, String>{
  DictType.vietPhrase: 'VietPhrase.txt',
  DictType.lacViet: 'LacViet.txt',
  DictType.mazii: 'Mazii.txt',
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

enum SudachiReadingsMode { sudachiFirst, jaViFirst, disabled }

/// Hiển thị cụm chỉ có trong từ điển phụ (LacViet > Nhật Việt > Mazii)
/// mà VietPhrase không có: tắt, sát khoảng cách, hoặc in nghiêng.
enum SecondaryPhraseDisplay { off, tight, italic }

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

/// Các từ điển popup khả dụng cho từng ngôn ngữ:
/// - Tiếng Nhật: không có Trung Việt (zhVi).
/// - Tiếng Trung: không có Nhật Việt (jaVi) và Mazii; mặc định là Lạc Việt.
List<LookupDictionaryType> availablePopupDictionariesFor(TranslationMode mode) {
  if (mode == TranslationMode.japanese) {
    return LookupDictionaryType.values
        .where((type) => type != LookupDictionaryType.zhVi)
        .toList(growable: false);
  } else {
    return LookupDictionaryType.values
        .where(
          (type) =>
              type != LookupDictionaryType.jaVi &&
              type != LookupDictionaryType.mazii,
        )
        .toList(growable: false);
  }
}

class AppSettings {
  /// Đường dẫn file dict nguồn theo ngôn ngữ (JP/CN mỗi bộ riêng).
  final Map<TranslationMode, Map<DictType, String>> dictPaths;
  final TranslationMode defaultMode;
  final TranslationAlgorithm translationAlgorithm;

  /// Names thắng cụm VietPhrase dài hơn tại cùng vị trí (UserDict vẫn cao nhất).
  final bool prioritizeNames;

  /// Phạm vi từ điển được phép lấp placeholder `{0}` của Luật Nhân.
  final PersonRuleScope personRuleScope;

  /// Hiện tab kết quả hậu xử lý và áp file regex của ngôn ngữ hiện tại.
  final bool postProcessingEnabled;

  /// Mode Nhật: gộp run số kanji không match thành số Ả Rập (三百二十五 → 325).
  final bool joinKanjiNumerals;

  /// Mode Nhật: chuẩn hoá halfwidth katakana (ｱｲｳ → アイウ) trước khi tra.
  final bool normalizeHalfwidthKana;

  /// Mode Trung: quy phồn thể → giản thể trước khi tra (時間 → 时间). Văn bản
  /// trong ô Nguồn giữ nguyên bản gốc. Không áp dụng cho mode Nhật.
  final bool convertTraditionalToSimplified;

  /// Mode Nhật: merge từ điển biến thể Sudachi (data/jp/SudachiVariants.txt)
  /// dưới VietPhrase. Đổi setting → nạp lại bộ từ điển.
  final bool sudachiVariants;

  /// Mode Nhật: cấu hình phát âm kana từ data/jp/SudachiReadings.txt
  /// trong ô Nghĩa.
  final SudachiReadingsMode sudachiReadings;

  /// Mode Nhật: cách hiển thị cụm chỉ có trong từ điển phụ mà VietPhrase
  /// không có (kana sát khoảng cách hoặc in nghiêng).
  final SecondaryPhraseDisplay secondaryPhraseDisplay;

  /// Chính sách repair Key thuần Hán (màn Sửa từ điển) — chỉnh ở Cài đặt.
  final RepairPolicy repairPolicy;

  /// Cỡ chữ + font riêng cho từng ô.
  final Map<PaneId, PaneFont> paneFonts;

  /// Hệ số cỡ chữ giao diện (chrome: nhãn rail, nút, dialog, cài đặt, tab, menu…).
  /// 1.0 = mặc định. KHÔNG đổi cỡ chữ nội dung các ô dịch (ô dùng cỡ riêng qua
  /// [paneFonts]) — chỉ scale text lấy từ `theme.textTheme`.
  final double uiFontScale;

  /// Font chữ giao diện ('' = mặc định hệ thống — Segoe UI). Áp cho toàn UI;
  /// các ô để "Mặc định hệ thống" cũng thừa hưởng font này.
  final String uiFontFamily;

  /// Chế độ giao diện sáng/tối/theo hệ thống.
  final ThemeMode themeMode;

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

  /// Kiểu hiển thị VietPhrase đa nghĩa trong tab đa nghĩa.
  final MultiMeaningDisplayMode multiMeaningDisplayMode;

  /// Giữ nguyên ngoặc kép CJK đặc biệt 『』《》〈〉〝〞〟 khi hiển thị
  /// (false → chuyển thành `"`). 「」 luôn chuyển thành `"`.
  final bool keepSpecialQuotes;

  /// Voice TTS đã chọn theo ngôn ngữ (`"name::locale"`; '' = tự động chọn).
  final String ttsVoiceJa;
  final String ttsVoiceZh;

  /// Tốc độ đọc TTS (0.1–1.0) theo từng ngôn ngữ.
  final double ttsSpeechRateJa;
  final double ttsSpeechRateZh;

  /// Các từ điển hiện trong popup ở ô Nguồn khi active một từ ở bất kỳ ô nào
  /// (Nguồn / VietPhrase / Hán Việt, tối đa 1) theo từng ngôn ngữ.
  final List<LookupDictionaryType> popupDictionaryTypesJa;
  final List<LookupDictionaryType> popupDictionaryTypesZh;

  /// Loại từ điển nào hiện trong ô Nghĩa và theo thứ tự nào, riêng từng ngôn ngữ.
  final MeaningPanelLayout meaningPanelJa;
  final MeaningPanelLayout meaningPanelZh;

  /// Các nguồn chạy khi bấm "Tra online" (rỗng = tắt hẳn tra online).
  final List<OnlineLookupSource> onlineLookupSources;

  /// Tự động kiểm tra bản cập nhật mới lúc khởi động.
  final bool autoCheckUpdates;

  /// Tự động đồng bộ (kéo) từ điển chung từ server lúc khởi động. Mặc định tắt.
  final bool autoSyncDictionary;

  /// Chu kỳ (ngày) nhắc cập nhật từ điển chung khi mở app. 0 = tắt nhắc,
  /// nhỏ nhất là [SyncReminder.minIntervalDays] (2 tuần).
  final int dictionarySyncReminderDays;

  /// Windows: nghe clipboard CJK và đăng ký Ctrl+Shift+V toàn hệ thống.
  final bool clipboardReaderEnabled;

  /// Thư mục `Glossary/` của AI_Translation_Bridge. Chỉ dùng khi đăng nhập
  /// quản trị: cho phép đẩy mục đang sửa sang `Global Glossary.json` JP/CN.
  final String glossaryDir;

  /// Tự động cập nhật Glossary khi bấm "Lưu từ" (nếu từ đã có trong Glossary).
  final bool autoUpdateGlossaryOnSave;

  /// Hiển thị thông báo Toast/SnackBar khi tự động cập nhật Glossary.
  final bool notifyOnGlossaryAutoUpdate;

  AppSettings({
    required this.dictPaths,
    required this.defaultMode,
    this.translationAlgorithm = TranslationAlgorithm.leftToRight,
    this.prioritizeNames = false,
    this.personRuleScope = PersonRuleScope.off,
    this.postProcessingEnabled = false,
    this.joinKanjiNumerals = true,
    this.normalizeHalfwidthKana = true,
    this.convertTraditionalToSimplified = true,
    this.sudachiVariants = true,
    this.sudachiReadings = SudachiReadingsMode.sudachiFirst,
    this.secondaryPhraseDisplay = SecondaryPhraseDisplay.tight,
    this.repairPolicy = RepairPolicy.addVariant,
    this.paneFonts = const {},
    this.uiFontScale = 1.0,
    this.uiFontFamily = '',
    this.themeMode = ThemeMode.system,
    this.syncServerUrl = defaultSyncServerUrl,
    this.isSyncServerUrlOverridden = false,
    this.columnsRatio = 0.42,
    this.leftSplitRatio = 0.6,
    this.rightSplitRatio = 0.6,
    this.katakanaColor = 0xFF2E7D32,
    this.bracketSingleMeaning = true,
    this.multiMeaningDisplayMode = MultiMeaningDisplayMode.visualHierarchy,
    this.keepSpecialQuotes = true,
    this.ttsVoiceJa = '',
    this.ttsVoiceZh = '',
    this.ttsSpeechRateJa = 0.5,
    this.ttsSpeechRateZh = 0.5,
    this.popupDictionaryTypesJa = const [],
    this.popupDictionaryTypesZh = const [LookupDictionaryType.lacViet],
    MeaningPanelLayout? meaningPanelJa,
    MeaningPanelLayout? meaningPanelZh,
    this.onlineLookupSources = OnlineLookupSource.values,
    this.autoCheckUpdates = true,
    this.autoSyncDictionary = false,
    this.dictionarySyncReminderDays = SyncReminder.defaultIntervalDays,
    this.clipboardReaderEnabled = false,
    this.glossaryDir = defaultGlossaryDir,
    this.autoUpdateGlossaryOnSave = true,
    this.notifyOnGlossaryAutoUpdate = true,
  }) : meaningPanelJa =
           meaningPanelJa ??
           MeaningPanelLayout.defaultsFor(TranslationMode.japanese),
       meaningPanelZh =
           meaningPanelZh ??
           MeaningPanelLayout.defaultsFor(TranslationMode.chinese);

  /// Voice đã chọn cho [mode] ('' = tự động).
  String ttsVoiceFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? ttsVoiceJa : ttsVoiceZh;

  /// Tốc độ đọc đã chọn cho [mode].
  double ttsSpeechRateFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? ttsSpeechRateJa : ttsSpeechRateZh;

  /// Từ điển popup đã chọn cho [mode].
  List<LookupDictionaryType> popupDictionaryTypesFor(TranslationMode mode) =>
      mode == TranslationMode.japanese
      ? popupDictionaryTypesJa
      : popupDictionaryTypesZh;

  /// Bố cục ô Nghĩa (loại nào hiện + thứ tự) cho [mode].
  MeaningPanelLayout meaningPanelLayoutFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? meaningPanelJa : meaningPanelZh;

  double get ttsSpeechRate => ttsSpeechRateJa;
  List<LookupDictionaryType> get popupDictionaryTypes => popupDictionaryTypesJa;

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
    PersonRuleScope? personRuleScope,
    bool? postProcessingEnabled,
    bool? joinKanjiNumerals,
    bool? normalizeHalfwidthKana,
    bool? convertTraditionalToSimplified,
    bool? sudachiVariants,
    SudachiReadingsMode? sudachiReadings,
    SecondaryPhraseDisplay? secondaryPhraseDisplay,
    RepairPolicy? repairPolicy,
    Map<PaneId, PaneFont>? paneFonts,
    double? uiFontScale,
    String? uiFontFamily,
    ThemeMode? themeMode,
    String? syncServerUrl,
    bool? isSyncServerUrlOverridden,
    double? columnsRatio,
    double? leftSplitRatio,
    double? rightSplitRatio,
    int? katakanaColor,
    bool? bracketSingleMeaning,
    MultiMeaningDisplayMode? multiMeaningDisplayMode,
    bool? keepSpecialQuotes,
    String? ttsVoiceJa,
    String? ttsVoiceZh,
    double? ttsSpeechRateJa,
    double? ttsSpeechRateZh,
    List<LookupDictionaryType>? popupDictionaryTypesJa,
    List<LookupDictionaryType>? popupDictionaryTypesZh,
    MeaningPanelLayout? meaningPanelJa,
    MeaningPanelLayout? meaningPanelZh,
    List<OnlineLookupSource>? onlineLookupSources,
    bool? autoCheckUpdates,
    bool? autoSyncDictionary,
    int? dictionarySyncReminderDays,
    bool? clipboardReaderEnabled,
    String? glossaryDir,
    bool? autoUpdateGlossaryOnSave,
    bool? notifyOnGlossaryAutoUpdate,
  }) => AppSettings(
    dictPaths: dictPaths ?? this.dictPaths,
    defaultMode: defaultMode ?? this.defaultMode,
    translationAlgorithm: translationAlgorithm ?? this.translationAlgorithm,
    prioritizeNames: prioritizeNames ?? this.prioritizeNames,
    personRuleScope: personRuleScope ?? this.personRuleScope,
    postProcessingEnabled: postProcessingEnabled ?? this.postProcessingEnabled,
    joinKanjiNumerals: joinKanjiNumerals ?? this.joinKanjiNumerals,
    normalizeHalfwidthKana:
        normalizeHalfwidthKana ?? this.normalizeHalfwidthKana,
    convertTraditionalToSimplified:
        convertTraditionalToSimplified ?? this.convertTraditionalToSimplified,
    sudachiVariants: sudachiVariants ?? this.sudachiVariants,
    sudachiReadings: sudachiReadings ?? this.sudachiReadings,
    secondaryPhraseDisplay:
        secondaryPhraseDisplay ?? this.secondaryPhraseDisplay,
    repairPolicy: repairPolicy ?? this.repairPolicy,
    paneFonts: paneFonts ?? this.paneFonts,
    uiFontScale: uiFontScale ?? this.uiFontScale,
    uiFontFamily: uiFontFamily ?? this.uiFontFamily,
    themeMode: themeMode ?? this.themeMode,
    syncServerUrl: syncServerUrl ?? this.syncServerUrl,
    isSyncServerUrlOverridden:
        isSyncServerUrlOverridden ?? this.isSyncServerUrlOverridden,
    columnsRatio: columnsRatio ?? this.columnsRatio,
    leftSplitRatio: leftSplitRatio ?? this.leftSplitRatio,
    rightSplitRatio: rightSplitRatio ?? this.rightSplitRatio,
    katakanaColor: katakanaColor ?? this.katakanaColor,
    bracketSingleMeaning: bracketSingleMeaning ?? this.bracketSingleMeaning,
    multiMeaningDisplayMode:
        multiMeaningDisplayMode ?? this.multiMeaningDisplayMode,
    keepSpecialQuotes: keepSpecialQuotes ?? this.keepSpecialQuotes,
    ttsVoiceJa: ttsVoiceJa ?? this.ttsVoiceJa,
    ttsVoiceZh: ttsVoiceZh ?? this.ttsVoiceZh,
    ttsSpeechRateJa: ttsSpeechRateJa ?? this.ttsSpeechRateJa,
    ttsSpeechRateZh: ttsSpeechRateZh ?? this.ttsSpeechRateZh,
    meaningPanelJa: meaningPanelJa ?? this.meaningPanelJa,
    meaningPanelZh: meaningPanelZh ?? this.meaningPanelZh,
    popupDictionaryTypesJa:
        popupDictionaryTypesJa ?? this.popupDictionaryTypesJa,
    popupDictionaryTypesZh:
        popupDictionaryTypesZh ?? this.popupDictionaryTypesZh,
    onlineLookupSources: onlineLookupSources ?? this.onlineLookupSources,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    autoSyncDictionary: autoSyncDictionary ?? this.autoSyncDictionary,
    dictionarySyncReminderDays:
        dictionarySyncReminderDays ?? this.dictionarySyncReminderDays,
    clipboardReaderEnabled:
        clipboardReaderEnabled ?? this.clipboardReaderEnabled,
    glossaryDir: glossaryDir ?? this.glossaryDir,
    autoUpdateGlossaryOnSave:
        autoUpdateGlossaryOnSave ?? this.autoUpdateGlossaryOnSave,
    notifyOnGlossaryAutoUpdate:
        notifyOnGlossaryAutoUpdate ?? this.notifyOnGlossaryAutoUpdate,
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
  static const _personRuleScopeKey = 'translate.personRuleScope';
  static const _postProcessingEnabledKey = 'translate.postProcessingEnabled';
  static const _joinKanjiNumeralsKey = 'translate.joinKanjiNumerals';
  static const _normalizeHalfwidthKanaKey = 'translate.normalizeHalfwidthKana';
  static const _trad2SimpKey = 'translate.convertTraditionalToSimplified';
  static const _sudachiVariantsKey = 'translate.sudachiVariants';
  static const _sudachiReadingsKey = 'translate.sudachiReadings';
  static const _secondaryPhraseDisplayKey = 'translate.secondaryPhraseDisplay';
  static const _repairPolicyKey = 'repairPolicy';
  static const _syncServerUrlKey = 'syncServerUrl';
  static const _columnsRatioKey = 'layout.columnsRatio';
  static const _leftSplitRatioKey = 'layout.leftSplitRatio';
  static const _rightSplitRatioKey = 'layout.rightSplitRatio';
  static const _katakanaColorKey = 'katakanaColor';
  static const _bracketSingleMeaningKey = 'display.bracketSingle';
  static const _multiMeaningDisplayModeKey = 'display.multiMeaningMode';
  static const _keepSpecialQuotesKey = 'display.keepSpecialQuotes';
  static const _ttsVoiceJaKey = 'tts.voice.ja';
  static const _ttsVoiceZhKey = 'tts.voice.zh';
  static const _ttsSpeechRateKey = 'tts.speechRate';
  static const _ttsSpeechRateJaKey = 'tts.speechRate.ja';
  static const _ttsSpeechRateZhKey = 'tts.speechRate.zh';
  static const _popupDictionaryTypesKey = 'lookup.popupDictionaries';
  static const _popupDictionaryTypesJaKey = 'lookup.popupDictionaries.ja';
  static const _popupDictionaryTypesZhKey = 'lookup.popupDictionaries.zh';
  static const _meaningPanelJaKey = 'lookup.meaningPanel.ja';
  static const _meaningPanelZhKey = 'lookup.meaningPanel.zh';
  static const _onlineLookupSourcesKey = 'lookup.onlineSources';
  static const _autoCheckUpdatesKey = 'update.autoCheckUpdates';
  static const _autoSyncDictionaryKey = 'dictionarySync.autoSync';
  static const _dictionarySyncReminderDaysKey = 'dictionarySync.reminderDays';
  static const _clipboardReaderEnabledKey = 'clipboard.readerEnabled';
  static const _glossaryDirKey = 'glossary.dir';
  static const _autoUpdateGlossaryOnSaveKey = 'glossary.autoUpdateOnSave';
  static const _notifyOnGlossaryAutoUpdateKey = 'glossary.notifyOnAutoUpdate';
  static String _fontSizeKey(PaneId id) => 'paneFont.${id.name}.size';
  static String _fontFamilyKey(PaneId id) => 'paneFont.${id.name}.family';
  static const _uiFontScaleKey = 'ui.fontScale';
  static const _uiFontFamilyKey = 'ui.fontFamily';
  static const _themeModeKey = 'ui.themeMode';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final defaults = AppSettings.defaults();
    final envUrl = _loadSyncServerUrlFromEnv();
    final isOverridden = envUrl != defaultSyncServerUrl;
    final legacyTtsRate = prefs.getDouble(_ttsSpeechRateKey);
    final legacyPopupDicts = prefs.getStringList(_popupDictionaryTypesKey);

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
      personRuleScope:
          PersonRuleScope.values.asNameMap()[prefs.getString(
            _personRuleScopeKey,
          )] ??
          PersonRuleScope.off,
      postProcessingEnabled: prefs.getBool(_postProcessingEnabledKey) ?? false,
      joinKanjiNumerals: prefs.getBool(_joinKanjiNumeralsKey) ?? true,
      normalizeHalfwidthKana: prefs.getBool(_normalizeHalfwidthKanaKey) ?? true,
      convertTraditionalToSimplified: prefs.getBool(_trad2SimpKey) ?? true,
      sudachiVariants: prefs.getBool(_sudachiVariantsKey) ?? true,
      sudachiReadings: () {
        final val = prefs.get(_sudachiReadingsKey);
        if (val is String) {
          return SudachiReadingsMode.values.asNameMap()[val] ??
              SudachiReadingsMode.sudachiFirst;
        } else if (val is bool) {
          return val
              ? SudachiReadingsMode.jaViFirst
              : SudachiReadingsMode.disabled;
        }
        return SudachiReadingsMode.sudachiFirst;
      }(),
      secondaryPhraseDisplay:
          SecondaryPhraseDisplay.values.asNameMap()[prefs.getString(
            _secondaryPhraseDisplayKey,
          )] ??
          SecondaryPhraseDisplay.tight,
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
      uiFontScale: prefs.getDouble(_uiFontScaleKey) ?? 1.0,
      uiFontFamily: prefs.getString(_uiFontFamilyKey) ?? '',
      themeMode:
          ThemeMode.values.asNameMap()[prefs.getString(_themeModeKey)] ??
          ThemeMode.system,
      syncServerUrl: isOverridden
          ? envUrl
          : (prefs.getString(_syncServerUrlKey) ?? defaultSyncServerUrl),
      isSyncServerUrlOverridden: isOverridden,
      columnsRatio: prefs.getDouble(_columnsRatioKey) ?? 0.42,
      leftSplitRatio: prefs.getDouble(_leftSplitRatioKey) ?? 0.6,
      rightSplitRatio: prefs.getDouble(_rightSplitRatioKey) ?? 0.6,
      katakanaColor: prefs.getInt(_katakanaColorKey) ?? 0xFF2E7D32,
      bracketSingleMeaning: prefs.getBool(_bracketSingleMeaningKey) ?? true,
      multiMeaningDisplayMode: MultiMeaningDisplayMode.fromKey(
        prefs.getString(_multiMeaningDisplayModeKey),
      ),
      keepSpecialQuotes: prefs.getBool(_keepSpecialQuotesKey) ?? true,
      ttsVoiceJa: prefs.getString(_ttsVoiceJaKey) ?? '',
      ttsVoiceZh: prefs.getString(_ttsVoiceZhKey) ?? '',
      ttsSpeechRateJa:
          prefs.getDouble(_ttsSpeechRateJaKey) ?? legacyTtsRate ?? 0.5,
      ttsSpeechRateZh:
          prefs.getDouble(_ttsSpeechRateZhKey) ?? legacyTtsRate ?? 0.5,
      meaningPanelJa: MeaningPanelLayout.decode(
        prefs.getString(_meaningPanelJaKey),
        TranslationMode.japanese,
      ),
      meaningPanelZh: MeaningPanelLayout.decode(
        prefs.getString(_meaningPanelZhKey),
        TranslationMode.chinese,
      ),
      popupDictionaryTypesJa: () {
        final saved =
            prefs.getStringList(_popupDictionaryTypesJaKey) ?? legacyPopupDicts;
        if (saved == null) return const <LookupDictionaryType>[];
        return saved
            .map((name) => LookupDictionaryType.values.asNameMap()[name])
            .whereType<LookupDictionaryType>()
            .where((type) => type != LookupDictionaryType.zhVi)
            .take(1)
            .toList(growable: false);
      }(),
      popupDictionaryTypesZh: () {
        final saved =
            prefs.getStringList(_popupDictionaryTypesZhKey) ?? legacyPopupDicts;
        if (saved == null) {
          return const <LookupDictionaryType>[LookupDictionaryType.lacViet];
        }
        return saved
            .map((name) => LookupDictionaryType.values.asNameMap()[name])
            .whereType<LookupDictionaryType>()
            .where(
              (type) =>
                  type != LookupDictionaryType.jaVi &&
                  type != LookupDictionaryType.mazii,
            )
            .take(1)
            .toList(growable: false);
      }(),
      onlineLookupSources: () {
        final saved = prefs.getStringList(_onlineLookupSourcesKey);
        if (saved == null) return OnlineLookupSource.values;
        return saved
            .map((name) => OnlineLookupSource.values.asNameMap()[name])
            .whereType<OnlineLookupSource>()
            .toList(growable: false);
      }(),
      autoCheckUpdates: prefs.getBool(_autoCheckUpdatesKey) ?? true,
      autoSyncDictionary: prefs.getBool(_autoSyncDictionaryKey) ?? false,
      dictionarySyncReminderDays: SyncReminder.normalizeIntervalDays(
        prefs.getInt(_dictionarySyncReminderDaysKey) ??
            SyncReminder.defaultIntervalDays,
      ),
      clipboardReaderEnabled:
          prefs.getBool(_clipboardReaderEnabledKey) ?? false,
      glossaryDir: prefs.getString(_glossaryDirKey) ?? defaultGlossaryDir,
      autoUpdateGlossaryOnSave:
          prefs.getBool(_autoUpdateGlossaryOnSaveKey) ?? true,
      notifyOnGlossaryAutoUpdate:
          prefs.getBool(_notifyOnGlossaryAutoUpdateKey) ?? true,
    );
  }

  Future<void> setAutoUpdateGlossaryOnSave(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_autoUpdateGlossaryOnSaveKey, value);
    state = state.copyWith(autoUpdateGlossaryOnSave: value);
  }

  Future<void> setNotifyOnGlossaryAutoUpdate(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_notifyOnGlossaryAutoUpdateKey, value);
    state = state.copyWith(notifyOnGlossaryAutoUpdate: value);
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

  Future<void> setTtsSpeechRate(TranslationMode mode, double value) async {
    final v = value.clamp(0.1, 1.0);
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == TranslationMode.japanese) {
      await prefs.setDouble(_ttsSpeechRateJaKey, v);
      state = state.copyWith(ttsSpeechRateJa: v);
    } else {
      await prefs.setDouble(_ttsSpeechRateZhKey, v);
      state = state.copyWith(ttsSpeechRateZh: v);
    }
  }

  Future<void> setPopupDictionaryTypes(
    TranslationMode mode,
    Iterable<LookupDictionaryType> values,
  ) async {
    final available = availablePopupDictionariesFor(mode);
    final normalized = values
        .where(available.contains)
        .toSet()
        .take(1)
        .toList(growable: false);
    final prefs = ref.read(sharedPreferencesProvider);
    final key = mode == TranslationMode.japanese
        ? _popupDictionaryTypesJaKey
        : _popupDictionaryTypesZhKey;
    await prefs.setStringList(
      key,
      normalized.map((value) => value.name).toList(growable: false),
    );
    if (mode == TranslationMode.japanese) {
      state = state.copyWith(popupDictionaryTypesJa: normalized);
    } else {
      state = state.copyWith(popupDictionaryTypesZh: normalized);
    }
  }

  /// Lưu bố cục ô Nghĩa (loại nào hiện + thứ tự) cho [mode].
  Future<void> setMeaningPanelLayout(
    TranslationMode mode,
    MeaningPanelLayout layout,
  ) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final key = mode == TranslationMode.japanese
        ? _meaningPanelJaKey
        : _meaningPanelZhKey;
    await prefs.setString(key, layout.encode());
    state = mode == TranslationMode.japanese
        ? state.copyWith(meaningPanelJa: layout)
        : state.copyWith(meaningPanelZh: layout);
  }

  /// Bật/tắt từng nguồn tra online; giữ đúng thứ tự khai báo của enum.
  Future<void> setOnlineLookupSources(
    Iterable<OnlineLookupSource> values,
  ) async {
    final selected = values.toSet();
    final normalized = OnlineLookupSource.values
        .where(selected.contains)
        .toList(growable: false);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(
      _onlineLookupSourcesKey,
      normalized.map((value) => value.name).toList(growable: false),
    );
    state = state.copyWith(onlineLookupSources: normalized);
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

  Future<void> setMultiMeaningDisplayMode(MultiMeaningDisplayMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_multiMeaningDisplayModeKey, mode.key);
    state = state.copyWith(multiMeaningDisplayMode: mode);
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

  Future<void> setPersonRuleScope(PersonRuleScope value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_personRuleScopeKey, value.name);
    state = state.copyWith(personRuleScope: value);
  }

  Future<void> setPostProcessingEnabled(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_postProcessingEnabledKey, value);
    state = state.copyWith(postProcessingEnabled: value);
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

  Future<void> setConvertTraditionalToSimplified(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_trad2SimpKey, value);
    state = state.copyWith(convertTraditionalToSimplified: value);
  }

  Future<void> setSudachiVariants(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_sudachiVariantsKey, value);
    state = state.copyWith(sudachiVariants: value);
  }

  Future<void> setSudachiReadings(SudachiReadingsMode value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_sudachiReadingsKey, value.name);
    state = state.copyWith(sudachiReadings: value);
  }

  Future<void> setSecondaryPhraseDisplay(SecondaryPhraseDisplay value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_secondaryPhraseDisplayKey, value.name);
    state = state.copyWith(secondaryPhraseDisplay: value);
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

  /// Hệ số cỡ chữ giao diện (0.8–1.4). Áp ngay cho toàn UI qua theme.
  Future<void> setUiFontScale(double value) async {
    final v = value.clamp(0.8, 1.4);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_uiFontScaleKey, v);
    state = state.copyWith(uiFontScale: v);
  }

  /// Font chữ giao diện ('' = mặc định hệ thống).
  Future<void> setUiFontFamily(String value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_uiFontFamilyKey, value);
    state = state.copyWith(uiFontFamily: value);
  }

  /// Chế độ giao diện (ThemeMode.light / dark / system).
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_themeModeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setSyncServerUrl(String value) async {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_syncServerUrlKey, normalized);
    state = state.copyWith(syncServerUrl: normalized);
  }

  Future<void> setAutoCheckUpdates(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_autoCheckUpdatesKey, value);
    state = state.copyWith(autoCheckUpdates: value);
  }

  Future<void> setAutoSyncDictionary(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_autoSyncDictionaryKey, value);
    state = state.copyWith(autoSyncDictionary: value);
  }

  Future<void> setDictionarySyncReminderDays(int value) async {
    final normalized = SyncReminder.normalizeIntervalDays(value);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_dictionarySyncReminderDaysKey, normalized);
    state = state.copyWith(dictionarySyncReminderDays: normalized);
  }

  Future<void> setClipboardReaderEnabled(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_clipboardReaderEnabledKey, value);
    state = state.copyWith(clipboardReaderEnabled: value);
  }

  Future<void> setGlossaryDir(String value) async {
    final normalized = value.trim();
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_glossaryDirKey, normalized);
    state = state.copyWith(glossaryDir: normalized);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
