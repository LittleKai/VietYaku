import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../application/update_controller.dart';

/// Hiển thị dialog "có bản cập nhật mới" nếu trạng thái hiện tại là [UpdatePhase.available].
Future<void> maybeShowUpdateDialog(BuildContext context, WidgetRef ref) async {
  final state = ref.read(updateControllerProvider);
  if (state.phase != UpdatePhase.available) return;

  await showAppDialog<void>(
    context: context,
    icon: Icons.system_update_alt_outlined,
    title: 'Có bản cập nhật mới',
    description: state.release?.tagName,
    width: 480,
    content: const _UpdateDialogContent(),
    actionsBuilder: (dialogContext) => [
      _UpdateDialogActions(dialogContext: dialogContext),
    ],
  );
}

class _UpdateDialogContent extends ConsumerWidget {
  const _UpdateDialogContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<UpdateState>(updateControllerProvider, (previous, next) {
      if (next.phase == UpdatePhase.idle &&
          previous?.phase == UpdatePhase.installing) {
        Navigator.of(context).maybePop();
      }
    });

    switch (state.phase) {
      case UpdatePhase.downloading:
      case UpdatePhase.installing:
        final progress = state.downloadProgress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.phase == UpdatePhase.downloading
                  ? 'Đang tải bản cập nhật...'
                  : 'Đang cài đặt...',
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress > 0 ? progress : null),
            if (progress > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      case UpdatePhase.error:
        return Text(
          state.message ?? 'Đã xảy ra lỗi khi cập nhật.',
          style: TextStyle(color: scheme.error),
        );
      default:
        final body = state.release?.body.trim();
        return Text(
          body != null && body.isNotEmpty
              ? body
              : 'Đã có phiên bản mới.',
        );
    }
  }
}

class _UpdateDialogActions extends ConsumerWidget {
  const _UpdateDialogActions({required this.dialogContext});

  final BuildContext dialogContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);

    switch (state.phase) {
      case UpdatePhase.downloading:
      case UpdatePhase.installing:
        return const SizedBox.shrink();
      case UpdatePhase.error:
        return FilledButton(
          onPressed: () {
            controller.dismiss();
            Navigator.of(dialogContext).pop();
          },
          child: const Text('Đóng'),
        );
      default:
        final hasAsset = state.matchedAsset != null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                controller.skipCurrentVersion();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Bỏ qua bản này'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                controller.dismiss();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Để sau'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (hasAsset) {
                  controller.downloadAndInstall();
                } else {
                  controller.openReleasePage();
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(hasAsset ? 'Cập nhật ngay' : 'Mở trang GitHub'),
            ),
          ],
        );
    }
  }
}
