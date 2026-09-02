import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_paths.dart';
import '../domain/ai_service_config.dart';

class AiSettingsRepository {
  final AppPaths paths;
  final SharedPreferences prefs;

  AiSettingsRepository(this.paths, this.prefs);

  File get aiSettingsFile =>
      File(p.join(paths.support.path, 'ai_settings.json'));

  static const _prefsKey = 'ai_translation_settings';

  /// Load cấu hình AI từ file `userdata/ai_settings.json` hoặc SharedPreferences
  Future<AiSettings> loadSettings() async {
    // 1. Đọc từ file userdata/ai_settings.json nếu có
    if (aiSettingsFile.existsSync()) {
      try {
        final content = await aiSettingsFile.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content);
          if (json is Map<String, dynamic>) {
            return AiSettings.fromJson(json);
          }
        }
      } catch (_) {}
    }

    // 2. Đọc từ SharedPreferences nếu có
    final prefsStr = prefs.getString(_prefsKey);
    if (prefsStr != null && prefsStr.isNotEmpty) {
      try {
        final json = jsonDecode(prefsStr);
        if (json is Map<String, dynamic>) {
          final settings = AiSettings.fromJson(json);
          // Ghi ra file để đồng bộ
          await saveSettings(settings);
          return settings;
        }
      } catch (_) {}
    }

    // 3. Khởi tạo mặc định
    final defaults = AiSettings.defaults();
    await saveSettings(defaults);
    return defaults;
  }

  /// Lưu cấu hình AI ra cả file userdata và SharedPreferences
  Future<void> saveSettings(AiSettings settings) async {
    final jsonStr = jsonEncode(settings.toJson());
    try {
      await aiSettingsFile.parent.create(recursive: true);
      await aiSettingsFile.writeAsString(jsonStr);
    } catch (_) {}
    await prefs.setString(_prefsKey, jsonStr);
  }
}
