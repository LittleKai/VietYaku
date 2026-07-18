import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_provider.dart';
import '../application/viet_draft.dart';

/// Ô "Bản dịch Việt": người dùng tự gõ/chỉnh bản dịch thuần Việt. Luôn hiển thị
/// và luôn trống mặc định — dịch lại không xoá nội dung đang gõ. Nhận từ chèn
/// vào từ menu chuột phải ô VietPhrase (qua vietDraftControllerProvider).
class VietPane extends ConsumerWidget {
  const VietPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(vietDraftControllerProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Bản dịch Việt',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy bản dịch Việt',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã copy bản dịch Việt'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Xoá bản dịch',
                onPressed: () => controller.clear(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: ref.watch(
                settingsProvider.select((s) => s.paneTextStyleFor(PaneId.viet)),
              ),
              decoration: InputDecoration(
                hintText: 'Nhập hoặc chỉnh sửa bản dịch thuần Việt tại đây...',
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
