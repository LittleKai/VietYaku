import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// Tỉ lệ diện tích màn hình tối thiểu để coi cửa sổ là đang phóng to thật.
/// Cửa sổ maximize luôn phủ ~95% (chỉ hụt phần thanh tác vụ), còn cửa sổ ở
/// kích thước thường (1200×760) chỉ phủ dưới 50% trên mọi màn hình ≥ FullHD.
const double _maximizedCoverage = 0.9;

/// Cửa sổ có cờ maximized nhưng kích thước vẫn là kích thước thường hay không.
///
/// Windows có thể giữ `WS_MAXIMIZE` (nút title bar hiện icon Restore) mà khung
/// cửa sổ đã bị `SetWindowPos` thu nhỏ lại — xem [ensureWindowMaximized].
bool boundsLookMaximized(Size window, Size display) {
  if (display.width <= 0 || display.height <= 0) return true;
  final coverage =
      (window.width * window.height) / (display.width * display.height);
  return coverage >= _maximizedCoverage;
}

/// Phóng to cửa sổ lúc khởi động, và sửa cả trạng thái phóng to giả.
///
/// `main()` đã gọi `maximize()` trước khung hình đầu tiên, nhưng WM_DPICHANGED
/// (đổi màn hình / đổi mức scale lúc khởi động) từng ập tới ngay sau đó và gọi
/// `SetWindowPos` với kích thước thường: cờ `WS_MAXIMIZE` vẫn còn nên nút title
/// bar hiện icon Restore trong khi cửa sổ vẫn bé — bấm phóng to không có tác
/// dụng vì Windows nghĩ đã phóng to rồi. Runner đã bỏ qua resize đó khi cửa sổ
/// đang maximize; hàm này dọn nốt trường hợp trạng thái đã lệch trước khi
/// khung hình đầu tiên kịp chạy.
Future<void> ensureWindowMaximized() async {
  if (!await windowManager.isMaximized()) {
    await windowManager.maximize();
    return;
  }
  final display = PlatformDispatcher.instance.views.first.display;
  final logicalDisplay = Size(
    display.size.width / display.devicePixelRatio,
    display.size.height / display.devicePixelRatio,
  );
  final bounds = await windowManager.getBounds();
  if (boundsLookMaximized(bounds.size, logicalDisplay)) return;
  await windowManager.unmaximize();
  await windowManager.maximize();
}
