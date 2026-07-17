import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/tts_button.dart';
import '../../settings/settings_provider.dart';
import '../application/lookup_controller.dart';
import '../application/translation_controller.dart';

/// Panel "Nghĩa": header (từ + reading + 🔊 + ✏️) + nội dung tra từ điển.
class LacVietPanel extends ConsumerWidget {
  const LacVietPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(lookupControllerProvider);
    final mode =
        ref.watch(translationControllerProvider.select((s) => s.mode));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result == null)
          const Expanded(
            child: Center(
              child: Text('Nháy chuột vào chữ trong ô Nguồn\nhoặc kết quả dịch',
                  textAlign: TextAlign.center),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.matchedKey ?? result.word,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (result.reading != null || result.hanViet != null)
                        Text(
                          [
                            if (result.reading != null) result.reading!,
                            if (result.hanViet != null)
                              'Hán Việt: ${result.hanViet}',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const _OnlineLookupButton(),
                TtsButton(
                  textProvider: () => result.matchedKey ?? result.word,
                  mode: mode,
                  tooltip: 'Đọc từ',
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Sửa nghĩa (UserDict — ưu tiên cao nhất)',
                  onPressed: () => showEntryEditDialog(context, ref,
                      word: result.word, toNames: false),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                result.sections.isEmpty
                    ? 'Không tìm thấy trong từ điển.'
                    : result.sections
                        .map((s) => s.displayText)
                        .join('\n-----------------\n'),
                style: ref.watch(
                    settingsProvider.select((s) => s.paneTextStyle())),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Nút tra thêm nghĩa online (Nhật: Mazii, Trung: Google Dịch).
class _OnlineLookupButton extends ConsumerStatefulWidget {
  const _OnlineLookupButton();

  @override
  ConsumerState<_OnlineLookupButton> createState() =>
      _OnlineLookupButtonState();
}

class _OnlineLookupButtonState extends ConsumerState<_OnlineLookupButton> {
  bool _loading = false;

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final ok = await ref
        .read(lookupControllerProvider.notifier)
        .fetchOnlineMeaning();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Không lấy được nghĩa online (mạng hoặc không có).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return IconButton(
      icon: const Icon(Icons.travel_explore),
      tooltip: 'Tra thêm nghĩa online (Nhật: Mazii, Trung: Google Dịch)',
      onPressed: _fetch,
    );
  }
}
