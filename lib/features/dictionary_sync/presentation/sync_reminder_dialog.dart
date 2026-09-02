import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../../translation/domain/translation_engine.dart';
import '../application/dictionary_sync_controller.dart';
import '../domain/sync_reminder.dart';

/// Nhắc cập nhật từ điển chung khi đã quá chu kỳ kể từ lần cập nhật (hoặc lần
/// trả lời hộp thoại) gần nhất. Không tới hạn thì không hiện gì.
Future<void> maybeShowSyncReminderDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final notifier = ref.read(dictionarySyncProvider.notifier);
  final baseline = notifier.reminderBaseline();
  if (!await notifier.isReminderDue()) return;
  if (!context.mounted) return;

  final days = baseline == null
      ? 0
      : SyncReminder.daysSince(baseline, DateTime.now());
  final accepted = await showAppDialog<bool>(
    context: context,
    icon: Icons.sync_outlined,
    title: 'Cập nhật từ điển chung',
    description: days > 0
        ? 'Đã $days ngày kể từ lần cập nhật gần nhất'
        : null,
    width: 460,
    content: const Text(
      'Kéo bản từ điển chung (VietPhrase / Lạc Việt) mới nhất từ server cho cả '
      'tiếng Nhật lẫn tiếng Trung?\n\n'
      'Đổi chu kỳ nhắc trong Cài đặt → Chung → Nhắc cập nhật từ điển.',
    ),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: const Text('Để sau'),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.sync, size: 18),
        label: const Text('Cập nhật ngay'),
        onPressed: () => Navigator.of(dialogContext).pop(true),
      ),
    ],
  );

  // Đã hỏi rồi: dời mốc lên hiện tại để không hỏi lại ở lần mở app kế tiếp.
  await notifier.markReminderPrompted();
  if (accepted != true) return;

  for (final mode in TranslationMode.values) {
    try {
      await notifier.sync(mode);
    } catch (_) {
      // Lỗi mạng đã vào state.message; vẫn thử ngôn ngữ còn lại.
    }
  }
  if (!context.mounted) return;
  final message = ref.read(dictionarySyncProvider).message;
  if (message == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
