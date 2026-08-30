import 'package:flutter/material.dart';

import '../../core/platform_features.dart';

class IconContextMenuItem {
  const IconContextMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Màu riêng cho icon; null → dùng màu mặc định của TextButton.
  final Color? iconColor;
}

/// Context menu riêng của ứng dụng, có icon và không tự chèn các lệnh sửa text.
class IconContextMenu extends StatelessWidget {
  const IconContextMenu({
    super.key,
    required this.anchors,
    required this.items,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<IconContextMenuItem> items;

  @override
  Widget build(BuildContext context) {
    // AdaptiveTextSelectionToolbar đổi hẳn cách xếp con theo nền tảng:
    // desktop → Column khung rộng cố định; Android/iOS → thanh ngang có nút
    // tràn. Ép `width: double.infinity` trên thanh ngang thì mỗi nút chiếm trọn
    // bề rộng và dồn hết vào menu tràn, nên chỉ bọc SizedBox ở bản desktop.
    final touch = PlatformFeatures.touchPrimary;
    return AdaptiveTextSelectionToolbar(
      anchors: anchors,
      children: [
        for (final item in items)
          if (touch)
            TextButton.icon(
              icon: Icon(item.icon, size: 18, color: item.iconColor),
              label: Text(item.label),
              onPressed: item.onPressed,
            )
          else
            // DesktopTextSelectionToolbar xếp con trong Column có
            // crossAxisAlignment mặc định (center) ở khung rộng cố định → nút
            // co theo nội dung và nằm giữa. Ép nút rộng hết khung thì
            // `alignment: centerLeft` mới có tác dụng (đúng cách Flutter làm
            // cho DesktopTextSelectionToolbarButton).
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: Icon(item.icon, size: 18, color: item.iconColor),
                label: Text(item.label),
                onPressed: item.onPressed,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
