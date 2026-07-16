import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/translation/domain/translation_engine.dart';
import '../dictionary/domain/dict_type.dart';

/// Thư mục dữ liệu QuickTranslator_Jap gốc (mặc định, đổi được trong Cài đặt).
const defaultSourceDir = r'C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap';

const dictFileNames = <DictType, String>{
  DictType.vietPhrase: 'VietPhrase.txt',
  DictType.lacViet: 'LacViet.txt',
  DictType.names: 'Names.txt',
  DictType.chinesePhienAm: 'ChinesePhienAmWords.txt',
  DictType.pronouns: 'Pronouns.txt',
};

class AppSettings {
  /// Đường dẫn 5 file dict nguồn.
  final Map<DictType, String> dictPaths;
  final TranslationMode defaultMode;
  final TranslationAlgorithm translationAlgorithm;

  /// Names thắng cụm VietPhrase dài hơn tại cùng vị trí (UserDict vẫn cao nhất).
  final bool prioritizeNames;

  const AppSettings({
    required this.dictPaths,
    required this.defaultMode,
    this.translationAlgorithm = TranslationAlgorithm.leftToRight,
    this.prioritizeNames = false,
  });

  AppSettings copyWith({
    Map<DictType, String>? dictPaths,
    TranslationMode? defaultMode,
    TranslationAlgorithm? translationAlgorithm,
    bool? prioritizeNames,
  }) =>
      AppSettings(
        dictPaths: dictPaths ?? this.dictPaths,
        defaultMode: defaultMode ?? this.defaultMode,
        translationAlgorithm: translationAlgorithm ?? this.translationAlgorithm,
        prioritizeNames: prioritizeNames ?? this.prioritizeNames,
      );

  static AppSettings defaults() => AppSettings(
        dictPaths: {
          for (final entry in dictFileNames.entries)
            entry.key: p.join(defaultSourceDir, entry.value),
        },
        defaultMode: TranslationMode.japanese,
      );
}

/// Override trong main() sau khi có SharedPreferences.getInstance().
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsNotifier extends Notifier<AppSettings> {
  static String _pathKey(DictType type) => 'dictPath.${type.name}';
  static const _modeKey = 'defaultMode';
  static const _algorithmKey = 'translationAlgorithm';
  static const _prioritizeNamesKey = 'prioritizeNames';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final defaults = AppSettings.defaults();
    return AppSettings(
      dictPaths: {
        for (final entry in defaults.dictPaths.entries)
          entry.key: prefs.getString(_pathKey(entry.key)) ?? entry.value,
      },
      defaultMode: prefs.getString(_modeKey) == TranslationMode.chinese.name
          ? TranslationMode.chinese
          : TranslationMode.japanese,
      translationAlgorithm: TranslationAlgorithm.values
              .asNameMap()[prefs.getString(_algorithmKey)] ??
          TranslationAlgorithm.leftToRight,
      prioritizeNames: prefs.getBool(_prioritizeNamesKey) ?? false,
    );
  }

  Future<void> setDictPath(DictType type, String path) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_pathKey(type), path);
    state = state.copyWith(dictPaths: {...state.dictPaths, type: path});
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
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
