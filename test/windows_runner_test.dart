import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rào chắn cho bẫy #33: mở cửa sổ Đồng bộ Glossary bằng `FlutterViewController`
/// thứ hai trong CÙNG tiến trình Windows làm crash `0xC0000005` trong ANGLE D3D11
/// (`rx::StateManager11::syncProgram` / `rx::StateManager11::updateState` /
/// `rx::Renderer11::drawArrays`) dưới cả Impeller lẫn Skia.
///
/// Cửa sổ Đồng bộ Glossary phải chạy trong tiến trình OS tách rời
/// (`CreateProcessW` với `--glossary-sync`) để mỗi Flutter engine sở hữu
/// ANGLE/D3D11 display độc lập, giao tiếp hai chiều qua `WM_COPYDATA`.
void main() {
  const flutterWindowCppPath = 'windows/runner/flutter_window.cpp';
  const mainCppPath = 'windows/runner/main.cpp';

  late String flutterWindowCpp;
  late String mainCpp;

  setUpAll(() {
    flutterWindowCpp = File(flutterWindowCppPath).readAsStringSync();
    mainCpp = File(mainCppPath).readAsStringSync();
  });

  test(
    'bug_33: cửa sổ Glossary Sync chạy tiến trình tách rời, không tạo FlutterWindow thứ hai trong cùng process',
    () {
      expect(
        flutterWindowCpp,
        isNot(contains('std::make_unique<FlutterWindow>')),
        reason:
            'Không được tạo FlutterWindow/FlutterViewController thứ hai trong '
            'cùng tiến trình Windows — hai raster thread dùng chung ANGLE '
            'EGLDisplay/Renderer11 gây access violation 0xC0000005.',
      );
      expect(flutterWindowCpp, contains('CreateProcessW'));
      expect(flutterWindowCpp, contains('--glossary-sync'));
      expect(flutterWindowCpp, contains('WM_COPYDATA'));
      expect(mainCpp, contains('--glossary-sync'));
      expect(mainCpp, contains('glossarySyncMain'));
    },
  );

  test(
    'OpenOrActivateGlossarySyncWindow phân biệt tiến trình đang khởi động với cửa sổ đã đóng đang teardown',
    () {
      final start = flutterWindowCpp.indexOf(
        'bool FlutterWindow::OpenOrActivateGlossarySyncWindow(',
      );
      final end = flutterWindowCpp.indexOf(
        'void FlutterWindow::CloseGlossarySyncChild()',
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = flutterWindowCpp.substring(start, end);
      expect(body, contains('!glossary_sync_registered_'));
      expect(body, contains('glossary_sync_registered_ = false;'));
    },
  );
}
