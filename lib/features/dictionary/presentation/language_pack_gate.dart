import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../application/language_pack_provider.dart';

/// Bọc [child]: trong lúc chép bộ từ điển từ assets ra đĩa (chỉ mobile — lần
/// chạy đầu hoặc ngay sau khi app lên phiên bản mới) thì thay bằng màn hình
/// tiến độ, vì việc này mất tới hàng phút và bar mảnh không nói được gì.
class LanguagePackGate extends ConsumerWidget {
  const LanguagePackGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(languagePackProgressProvider);
    if (progress == null) return child;
    return _PreparingView(progress: progress);
  }
}

String formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

class _PreparingView extends StatelessWidget {
  const _PreparingView({required this.progress});

  final SeedProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.menu_book_outlined, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Đang chuẩn bị bộ từ điển',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Chỉ chạy lần đầu (và sau mỗi lần cập nhật ứng dụng). '
                'Sau đó mở app là dùng được ngay, không cần mạng.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                progress.fileName.isEmpty
                    ? 'Hoàn tất — ${formatMegabytes(progress.bytesCopied)}'
                    : '${progress.fileName} '
                          '(${progress.fileIndex}/${progress.fileCount}) · '
                          '${formatMegabytes(progress.bytesCopied)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
