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

  Directory get rulesDir => Directory(p.join(support.path, 'rules'));

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
    await paths.rulesDir.create(recursive: true);
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

  /// Nền tảng không có bộ từ điển sẵn trên đĩa → phải chép từ assets ra.
  static bool get needsAssetSeeding => Platform.isAndroid || Platform.isIOS;

  /// Thư mục gốc chứa `jp/` và `cn/` trên mobile (`<support>/data`). Gán vào
  /// `defaultDataDir` trong `main()`; KHÔNG chép gì — việc chép do
  /// [seedLanguagePack] làm sau, theo từng ngôn ngữ.
  static Future<String> mobileDataRoot() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'data');
  }

  /// Lọc asset key của một bộ ngôn ngữ (`jp` / `cn`) từ danh sách asset đầy đủ.
  ///
  /// Tách riêng để test được mà không cần AssetBundle thật. Sắp xếp để tiến độ
  /// hiện ra ổn định giữa các lần chạy.
  static List<String> assetKeysForLanguage(
    Iterable<String> allAssets,
    String lang,
  ) {
    final prefix = 'data/$lang/';
    return allAssets.where((a) => a.startsWith(prefix)).toList()..sort();
  }

  /// Nội dung file đánh dấu đã seed xong. Đổi [signature] (phiên bản app) hoặc
  /// đổi số file trong bộ → chữ ký lệch → seed lại.
  static String seedMarkerContent(String signature, int assetCount) =>
      '$signature|$assetCount';

  static File _seedMarker(String dataRoot, String lang) =>
      File(p.join(dataRoot, lang, '.seeded'));

  /// Chép bộ từ điển của MỘT ngôn ngữ (assets `data/<lang>/**`) sang
  /// `<support>/data/<lang>`.
  ///
  /// Idempotent: file đánh dấu `.seeded` mang chữ ký phiên bản app + số file;
  /// khớp thì trả về ngay, không đụng đĩa. Chữ ký lệch (app vừa cập nhật, bộ
  /// từ điển trong APK đổi) thì ghi đè lại toàn bộ.
  ///
  /// [onProgress] được gọi TRƯỚC mỗi file, để UI hiện tên file đang chép.
  static Future<void> seedLanguagePack(
    String lang, {
    required String signature,
    void Function(SeedProgress progress)? onProgress,
  }) async {
    final dataRoot = await mobileDataRoot();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetKeysForLanguage(manifest.listAssets(), lang);
    if (assets.isEmpty) return;

    final marker = _seedMarker(dataRoot, lang);
    final expected = seedMarkerContent(signature, assets.length);
    if (marker.existsSync() && marker.readAsStringSync() == expected) return;

    final dir = Directory(p.join(dataRoot, lang));
    await dir.create(recursive: true);
    // Marker cũ phải biến mất TRƯỚC khi ghi: seed bị ngắt giữa chừng thì lần
    // sau vẫn thấy "chưa seed" và làm lại, thay vì tin vào bộ file dở dang.
    if (marker.existsSync()) await marker.delete();

    var copied = 0;
    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      onProgress?.call(
        SeedProgress(
          fileIndex: i + 1,
          fileCount: assets.length,
          fileName: p.posix.basename(asset),
          bytesCopied: copied,
        ),
      );
      // asset key dùng '/'; đổi sang separator nền tảng cho đường dẫn đích.
      final dest = File(p.joinAll([dataRoot, ...p.posix.split(asset).skip(1)]));
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await dest.writeAsBytes(bytes, flush: true);
      copied += bytes.length;
      // Bỏ tham chiếu ngay: file lớn nhất 41MB, giữ lại sẽ cộng dồn vào peak.
      await Future<void>.delayed(Duration.zero);
    }
    await marker.writeAsString(expected, flush: true);
    onProgress?.call(
      SeedProgress(
        fileIndex: assets.length,
        fileCount: assets.length,
        fileName: '',
        bytesCopied: copied,
      ),
    );
  }
}

/// Tiến độ chép bộ từ điển từ assets (chỉ mobile).
class SeedProgress {
  final int fileIndex;
  final int fileCount;
  final String fileName;
  final int bytesCopied;

  const SeedProgress({
    required this.fileIndex,
    required this.fileCount,
    required this.fileName,
    required this.bytesCopied,
  });

  double get fraction => fileCount == 0 ? 0 : fileIndex / fileCount;

  bool get isDone => fileIndex >= fileCount && fileName.isEmpty;
}
