import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/translation/domain/translation_engine.dart';
import '../dictionary/domain/dict_type.dart';

/// Bộ từ điển bundle trong dự án (data/jp, data/cn), đổi được trong Cài đặt.
const defaultDataDir = r'D:\Dev\Python\LittleKai_Ecosystem\VietYaku\data';

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

class AppSettings {
  /// Đường dẫn file dict nguồn theo ngôn ngữ (JP/CN mỗi bộ riêng).
  final Map<TranslationMode, Map<DictType, String>> dictPaths;
  final TranslationMode defaultMode;
  final TranslationAlgorithm translationAlgorithm;

  /// Names thắng cụm VietPhrase dài hơn tại cùng vị trí (UserDict vẫn cao nhất).
  final bool prioritizeNames;

  /// Cỡ chữ và font của các ô Nguồn/Kết quả/Nghĩa ('' = font hệ thống).
  final double paneFontSize;
  final String paneFontFamily;

  const AppSettings({
    required this.dictPaths,
    required this.defaultMode,
    this.translationAlgorithm = TranslationAlgorithm.leftToRight,
    this.prioritizeNames = false,
    this.paneFontSize = 14,
    this.paneFontFamily = '',
  });

  /// Style chữ áp cho nội dung các ô.
  TextStyle paneTextStyle({double height = 1.5}) => TextStyle(
        fontSize: paneFontSize,
        fontFamily: paneFontFamily.isEmpty ? null : paneFontFamily,
        height: height,
      );

  Map<DictType, String> dictPathsFor(TranslationMode mode) =>
      dictPaths[mode]!;

  AppSettings copyWith({
    Map<TranslationMode, Map<DictType, String>>? dictPaths,
    TranslationMode? defaultMode,
    TranslationAlgorithm? translationAlgorithm,
    bool? prioritizeNames,
    double? paneFontSize,
    String? paneFontFamily,
  }) =>
      AppSettings(
        dictPaths: dictPaths ?? this.dictPaths,
        defaultMode: defaultMode ?? this.defaultMode,
        translationAlgorithm: translationAlgorithm ?? this.translationAlgorithm,
        prioritizeNames: prioritizeNames ?? this.prioritizeNames,
        paneFontSize: paneFontSize ?? this.paneFontSize,
        paneFontFamily: paneFontFamily ?? this.paneFontFamily,
      );

  static AppSettings defaults() => AppSettings(
        dictPaths: {
          for (final mode in TranslationMode.values)
            mode: {
              for (final entry in dictFileNames.entries)
                entry.key:
                    p.join(defaultDataDir, modeDirNames[mode]!, entry.value),
            },
        },
        defaultMode: TranslationMode.japanese,
      );
}

/// Override trong main() sau khi có SharedPreferences.getInstance().
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsNotifier extends Notifier<AppSettings> {
  static String _pathKey(TranslationMode mode, DictType type) =>
      'dictPath.${mode.name}.${type.name}';
  static const _modeKey = 'defaultMode';
  static const _algorithmKey = 'translationAlgorithm';
  static const _prioritizeNamesKey = 'prioritizeNames';
  static const _paneFontSizeKey = 'paneFontSize';
  static const _paneFontFamilyKey = 'paneFontFamily';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final defaults = AppSettings.defaults();
    return AppSettings(
      dictPaths: {
        for (final modeEntry in defaults.dictPaths.entries)
          modeEntry.key: {
            for (final entry in modeEntry.value.entries)
              entry.key: prefs.getString(_pathKey(modeEntry.key, entry.key)) ??
                  entry.value,
          },
      },
      defaultMode: prefs.getString(_modeKey) == TranslationMode.chinese.name
          ? TranslationMode.chinese
          : TranslationMode.japanese,
      translationAlgorithm: TranslationAlgorithm.values
              .asNameMap()[prefs.getString(_algorithmKey)] ??
          TranslationAlgorithm.leftToRight,
      prioritizeNames: prefs.getBool(_prioritizeNamesKey) ?? false,
      paneFontSize: prefs.getDouble(_paneFontSizeKey) ?? 14,
      paneFontFamily: prefs.getString(_paneFontFamilyKey) ?? '',
    );
  }

  Future<void> setDictPath(
      TranslationMode mode, DictType type, String path) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_pathKey(mode, type), path);
    state = state.copyWith(dictPaths: {
      ...state.dictPaths,
      mode: {...state.dictPaths[mode]!, type: path},
    });
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

  Future<void> setPaneFontSize(double value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_paneFontSizeKey, value);
    state = state.copyWith(paneFontSize: value);
  }

  Future<void> setPaneFontFamily(String value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_paneFontFamilyKey, value);
    state = state.copyWith(paneFontFamily: value);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
