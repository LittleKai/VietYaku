import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'features/dictionary/application/dictionaries_provider.dart';
import 'features/settings/settings_provider.dart';
import 'features/translation/domain/translation_engine.dart';

Future<void> _initDefaultDataDir({required bool isDesktop}) async {
  if (isDesktop) {
    // Tự động tìm đường dẫn chứa từ điển (release build dùng data/flutter_assets/data)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final relativeReleaseData = p.join(
      exeDir,
      'data',
      'flutter_assets',
      'data',
    );
    if (Directory(relativeReleaseData).existsSync()) {
      defaultDataDir = relativeReleaseData;
    } else {
      final localData = p.join(Directory.current.path, 'data');
      if (Directory(localData).existsSync()) {
        defaultDataDir = localData;
      }
    }
  } else {
    // Mobile: đường dẫn dev tuyệt đối không tồn tại → trỏ defaultDataDir vào
    // app storage TRƯỚC khi SettingsNotifier.build() đọc. Việc chép ~92MB
    // assets ra đĩa KHÔNG làm ở đây (sẽ treo màn hình đen tới mức ANR) —
    // languagePackProvider chép lười theo ngôn ngữ, có màn hình tiến độ.
    defaultDataDir = await AppPaths.mobileDataRoot();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // window_manager chỉ chạy trên desktop; Android/iOS bỏ qua.
  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  await _initDefaultDataDir(isDesktop: isDesktop);
  if (isDesktop) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1200, 760),
      minimumSize: Size(1000, 640),
      center: true,
      title: 'VietYaku',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.maximize();
      await windowManager.focus();
    });
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VietYakuApp(),
    ),
  );
}

/// Entrypoint riêng cho cửa sổ Windows tách rời "Đồng bộ Glossary ↔ VietPhrase".
/// Chạy trên Flutter engine thứ hai nhưng dùng chung `userdata/` và chỉ nạp lớp
/// VietPhrase (`vietPhraseOnlyModeProvider = true`) để mở tức thì.
@pragma('vm:entry-point')
Future<void> glossarySyncMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  await _initDefaultDataDir(isDesktop: isDesktop);

  final prefs = await SharedPreferences.getInstance();
  final initialMode =
      args.isNotEmpty && args.first == TranslationMode.chinese.name
      ? TranslationMode.chinese
      : TranslationMode.japanese;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        vietPhraseOnlyModeProvider.overrideWithValue(true),
      ],
      child: GlossarySyncWindowApp(initialMode: initialMode),
    ),
  );
}
