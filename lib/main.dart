import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'features/settings/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // window_manager chỉ chạy trên desktop; Android/iOS bỏ qua.
  final isDesktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  if (isDesktop) {
    await windowManager.ensureInitialized();
    
    // Tự động tìm đường dẫn chứa từ điển (release build dùng data/flutter_assets/data)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final relativeReleaseData = p.join(exeDir, 'data', 'flutter_assets', 'data');
    if (Directory(relativeReleaseData).existsSync()) {
      defaultDataDir = relativeReleaseData;
    } else {
      final localData = p.join(Directory.current.path, 'data');
      if (Directory(localData).existsSync()) {
        defaultDataDir = localData;
      }
    }

    const windowOptions = WindowOptions(
      size: Size(1200, 760),
      minimumSize: Size(1000, 640),
      center: true,
      title: 'VietYaku',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  } else {
    // Mobile: từ điển không có ở đường dẫn dev tuyệt đối → seed từ assets
    // sang app storage, rồi trỏ defaultDataDir vào đó trước khi build settings.
    defaultDataDir = await AppPaths.seedBundledData();
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VietYakuApp(),
    ),
  );
}
