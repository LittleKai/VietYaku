import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/window_maximize.dart';

void main() {
  group('boundsLookMaximized', () {
    test('cửa sổ maximize thật (hụt thanh tác vụ dưới) → true', () {
      expect(
        boundsLookMaximized(const Size(1920, 1032), const Size(1920, 1080)),
        isTrue,
      );
    });

    test('thanh tác vụ dọc bên trái vẫn tính là maximize', () {
      expect(
        boundsLookMaximized(const Size(1858, 1080), const Size(1920, 1080)),
        isTrue,
      );
    });

    test('kích thước cửa sổ mặc định 1200x760 → không phải maximize', () {
      // Trạng thái lỗi: WS_MAXIMIZE còn nguyên (icon Restore) nhưng khung cửa
      // sổ đã bị WM_DPICHANGED thu về kích thước thường.
      expect(
        boundsLookMaximized(const Size(1200, 760), const Size(1920, 1080)),
        isFalse,
      );
    });

    test('màn hình nhỏ: 1280x800 maximize vẫn true', () {
      expect(
        boundsLookMaximized(const Size(1280, 752), const Size(1280, 800)),
        isTrue,
      );
    });

    test('kích thước màn hình không hợp lệ → không ép maximize lại', () {
      expect(
        boundsLookMaximized(const Size(1200, 760), Size.zero),
        isTrue,
      );
    });
  });
}
