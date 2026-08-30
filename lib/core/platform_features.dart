import 'dart:io';

import 'package:flutter/widgets.dart';

/// Dưới ngưỡng này (dp) dùng bố cục dọc + thanh điều hướng dưới thay cho
/// NavigationRail + các ô chia đôi kiểu desktop.
const compactWidthBreakpoint = 720.0;

bool isCompactWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < compactWidthBreakpoint;

/// Tính năng chỉ có nghĩa trên một số nền tảng.
///
/// Bố cục chia theo BỀ RỘNG (xem [isCompactWidth]); còn lớp này chia theo
/// NỀN TẢNG — thu hẹp cửa sổ Windows không được làm mất tính năng desktop.
class PlatformFeatures {
  /// Ép giá trị nền tảng trong test (test chạy trên host nên `Platform` luôn
  /// báo desktop). Nhớ trả về `null` ở `tearDown`.
  @visibleForTesting
  static bool? debugIsMobileOverride;

  static bool get isMobile =>
      debugIsMobileOverride ?? (Platform.isAndroid || Platform.isIOS);

  /// Chuyển đổi EPUB: cần hộp thoại mở/lưu file kiểu desktop
  /// (`getSaveLocation` không có tương đương trên Android).
  static bool get epubConverter => !isMobile;

  /// Đồng bộ Glossary ↔ VietPhrase: đọc/ghi `Global Glossary.json` của
  /// AI_Translation_Bridge — thư mục chỉ tồn tại trên máy dev Windows.
  static bool get glossarySync => !isMobile;

  /// Sửa từ điển (repair pipeline): xuất `*_JP.txt` cạnh file nguồn.
  static bool get dictionaryRepair => !isMobile;

  /// Không có chuột phải / hover → phải mở lối thao tác bằng chạm.
  static bool get touchPrimary => isMobile;
}
