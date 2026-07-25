import 'package:flutter/material.dart';

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
    return AdaptiveTextSelectionToolbar(
      anchors: anchors,
      children: [
        for (final item in items)
          TextButton.icon(
            icon: Icon(item.icon, size: 18, color: item.iconColor),
            label: Text(item.label),
            onPressed: item.onPressed,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
      ],
    );
  }
}
