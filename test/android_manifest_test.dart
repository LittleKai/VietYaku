import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rào chắn cho bẫy "Android release mất sạch tính năng mạng".
///
/// Flutter tự sinh `src/debug/` và `src/profile/AndroidManifest.xml` có sẵn
/// `INTERNET`, nên chạy `flutter run` luôn có mạng. Manifest merger chỉ gộp
/// chúng vào đúng build type tương ứng — thiếu ở `src/main/` là bản release
/// mất mạng mà quá trình phát triển không bao giờ lộ ra.
///
/// Test này đọc thẳng `src/main/AndroidManifest.xml`: gỡ một quyền ra là đỏ
/// ngay, không phải chờ tới lúc cài APK release lên máy thật.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';

  late String manifest;

  setUpAll(() {
    manifest = File(manifestPath).readAsStringSync();
  });

  test('$manifestPath khai báo đủ quyền bản release cần', () {
    // INTERNET: tra online, Google Dịch, kiểm tra cập nhật, đồng bộ từ điển.
    // REQUEST_INSTALL_PACKAGES: tự cài APK khi cập nhật trong app.
    for (final permission in [
      'android.permission.INTERNET',
      'android.permission.REQUEST_INSTALL_PACKAGES',
    ]) {
      expect(
        manifest,
        contains('<uses-permission android:name="$permission"/>'),
        reason:
            'Thiếu $permission ở manifest main. Bản debug/profile có sẵn quyền '
            'này nên lỗi chỉ xuất hiện ở APK release.',
      );
    }
  });

  test('$manifestPath giữ largeHeap cho bộ từ điển ~700k entry', () {
    expect(manifest, contains('android:largeHeap="true"'));
  });
}
