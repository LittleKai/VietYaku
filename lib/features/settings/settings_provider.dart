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

  const AppSettings({required this.dictPaths, required this.defaultMode});

  AppSettings copyWith({
    Map<DictType, String>? dictPaths,
    TranslationMode? defaultMode,
  }) =>
      AppSettings(
        dictPaths: dictPaths ?? this.dictPaths,
        defaultMode: defaultMode ?? this.defaultMode,
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
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
