import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thư mục dữ liệu ghi được của app.
///
/// - `cache/`         → snapshot .vydc
/// - `dictionaries/`  → từ điển đã sửa (*_JP.txt) + UserDict.txt + OnlineDict
///
/// QUY ĐỊNH: desktop KHÔNG lưu vào AppData / Application Support.
/// - release → `<thư mục chứa .exe>/userdata` (app chạy kiểu portable)
/// - debug/profile → `<repo>/data/userdata`
/// - Android/iOS → không có thư mục cạnh exe ghi được nên vẫn dùng
///   `getApplicationSupportDirectory()`.
class AppPaths {
  final Directory support;

  AppPaths(this.support);

  Directory get cacheDir => Directory(p.join(support.path, 'cache'));

  Directory get dictionariesDir =>
      Directory(p.join(support.path, 'dictionaries'));

  /// [variant] tách cache của cùng một file nguồn khi nội dung parse ra khác
  /// nhau (bộ dict Trung đã quy phồn→giản dùng variant riêng).
  String cacheFileFor(String sourcePath, {String variant = ''}) {
    final name = p.basenameWithoutExtension(sourcePath);
    final suffix = variant.isEmpty ? '' : '.$variant';
    return p.join(cacheDir.path, '$name$suffix.vydc');
  }

  static Future<AppPaths> init() async {
    final paths = AppPaths(await _supportDir());
    await paths.cacheDir.create(recursive: true);
    await paths.dictionariesDir.create(recursive: true);
    await paths._migrateFromAppData();
    return paths;
  }

  static Future<Directory> _supportDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationSupportDirectory();
    }
    final root = kReleaseMode
        ? p.dirname(Platform.resolvedExecutable)
        : p.join(Directory.current.path, 'data');
    return Directory(p.join(root, 'userdata'));
  }

  /// Chép `dictionaries/` từ chỗ cũ (AppData, các bản trước) sang chỗ mới đúng
  /// một lần — chỉ khi thư mục mới còn trống, để không đè dữ liệu đang dùng.
  Future<void> _migrateFromAppData() async {
    if (Platform.isAndroid || Platform.isIOS) return;
    if (dictionariesDir.listSync().isNotEmpty) return;
    final legacy = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'dictionaries'),
    );
    if (!legacy.existsSync() || legacy.path == dictionariesDir.path) return;
    for (final entity in legacy.listSync().whereType<File>()) {
      entity.copySync(p.join(dictionariesDir.path, p.basename(entity.path)));
    }
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
