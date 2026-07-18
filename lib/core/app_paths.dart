import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thư mục dữ liệu nội bộ của app (application support).
///
/// - `cache/`         → snapshot .vydc
/// - `dictionaries/`  → từ điển đã sửa (*_JP.txt) + UserDict.txt
class AppPaths {
  final Directory support;

  AppPaths(this.support);

  Directory get cacheDir => Directory(p.join(support.path, 'cache'));

  Directory get dictionariesDir =>
      Directory(p.join(support.path, 'dictionaries'));

  String cacheFileFor(String sourcePath) {
    final name = p.basenameWithoutExtension(sourcePath);
    return p.join(cacheDir.path, '$name.vydc');
  }

  static Future<AppPaths> init() async {
    final support = await getApplicationSupportDirectory();
    final paths = AppPaths(support);
    await paths.cacheDir.create(recursive: true);
    await paths.dictionariesDir.create(recursive: true);
    return paths;
  }

  /// Copy bộ từ điển bundle (assets `data/**`) sang `<support>/data` nếu file
  /// đích chưa tồn tại (idempotent). Dùng trên mobile — đường dẫn dev tuyệt đối
  /// không có trên máy. Trả về đường dẫn thư mục `data` để gán `defaultDataDir`.
  static Future<String> seedBundledData() async {
    final support = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(support.path, 'data'));
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().where((a) => a.startsWith('data/'));
    for (final asset in assets) {
      // asset key dùng '/'; đổi sang separator nền tảng cho đường dẫn đích.
      final dest = File(p.joinAll([support.path, ...p.posix.split(asset)]));
      if (await dest.exists()) continue;
      await dest.parent.create(recursive: true);
      final bytes = await rootBundle.load(asset);
      await dest.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }
    return dataDir.path;
  }
}
