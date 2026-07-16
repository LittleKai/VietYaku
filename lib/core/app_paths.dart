import 'dart:io';

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
}
