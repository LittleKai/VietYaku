import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/translation/domain/translation_engine.dart';
import '../dictionary/domain/dict_type.dart';
import '../repair/domain/jp_repair_pipeline.dart';

/// Bộ từ điển bundle trong dự án (data/jp, data/cn), đổi được trong Cài đặt.
const defaultDataDir = r'D:\Dev\Python\LittleKai_Ecosystem\VietYaku\data';
const defaultSyncServerUrl = String.fromEnvironment(
  'LITTLEKAI_SERVER_URL',
  defaultValue: 'http://localhost:5000',
);

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

  /// Chính sách repair Key thuần Hán (màn Sửa từ điển) — chỉnh ở Cài đặt.
  final RepairPolicy repairPolicy;

  /// Cỡ chữ + font riêng cho từng ô.
  final Map<PaneId, PaneFont> paneFonts;
  final String syncServerUrl;

  const AppSettings({
    required this.dictPaths,
    required this.defaultMode,
    this.translationAlgorithm = TranslationAlgorithm.leftToRight,
    this.prioritizeNames = false,
    this.repairPolicy = RepairPolicy.addVariant,
    this.paneFonts = const {},
    this.syncServerUrl = defaultSyncServerUrl,
  });

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
    RepairPolicy? repairPolicy,
    Map<PaneId, PaneFont>? paneFonts,
    String? syncServerUrl,
  }) => AppSettings(
    dictPaths: dictPaths ?? this.dictPaths,
    defaultMode: defaultMode ?? this.defaultMode,
    translationAlgorithm: translationAlgorithm ?? this.translationAlgorithm,
    prioritizeNames: prioritizeNames ?? this.prioritizeNames,
    repairPolicy: repairPolicy ?? this.repairPolicy,
    paneFonts: paneFonts ?? this.paneFonts,
    syncServerUrl: syncServerUrl ?? this.syncServerUrl,
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
  static const _repairPolicyKey = 'repairPolicy';
  static const _syncServerUrlKey = 'syncServerUrl';
  static String _fontSizeKey(PaneId id) => 'paneFont.${id.name}.size';
  static String _fontFamilyKey(PaneId id) => 'paneFont.${id.name}.family';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final defaults = AppSettings.defaults();
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
      syncServerUrl: prefs.getString(_syncServerUrlKey) ?? defaultSyncServerUrl,
    );
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
