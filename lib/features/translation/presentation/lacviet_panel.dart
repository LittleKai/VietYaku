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
    final mode = ref.watch(translationControllerProvider.select((s) => s.mode));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result == null)
          const Expanded(
            child: Center(
              child: Text(
                'Nháy chuột vào chữ trong ô Nguồn\nhoặc kết quả dịch',
                textAlign: TextAlign.center,
              ),
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
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
                  onPressed: () => showEntryEditDialog(
                    context,
                    ref,
                    word: result.word,
                    toNames: false,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: result.sections.isEmpty
                  ? SelectableText(
                      'Không tìm thấy trong từ điển.',
                      style: ref.watch(
                        settingsProvider.select(
                          (s) => s.paneTextStyleFor(PaneId.meaning),
                        ),
                      ),
                    )
                  : _MeaningSections(sections: result.sections),
            ),
          ),
        ],
      ],
    );
  }
}

/// Màu nhãn `<<Từ điển>>` theo loại từ điển trong ô Nghĩa.
Color meaningLabelColor(String label, ColorScheme scheme) {
  switch (label) {
    case 'UserDict':
      return scheme.tertiary;
    case 'Names':
      return const Color(0xFF00897B); // teal
    case 'VietPhrase':
      return const Color(0xFF3949AB); // indigo
    case 'Lạc Việt':
      return const Color(0xFFD81B60); // pink
    case 'Nhật Việt':
      return const Color(0xFFE65100); // deep orange
    case 'Cedict':
    case 'Babylon':
      return const Color(0xFF6A1B9A); // purple
    case 'Thiều Chửu':
      return const Color(0xFF00838F); // cyan
    case 'Trung Việt':
      return const Color(0xFFC62828); // red
    case 'Mazii':
      return const Color(0xFF2E7D32); // green
    case 'Google Dịch':
      return const Color(0xFF1565C0); // blue
    default:
      return scheme.primary;
  }
}

/// Danh sách mục tra từ điển, mỗi mục có nhãn `<<Từ điển>>` màu riêng.
class _MeaningSections extends ConsumerWidget {
  const _MeaningSections({required this.sections});

  final List<LookupSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final style = ref.watch(
      settingsProvider.select((s) => s.paneTextStyleFor(PaneId.meaning)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0)
            Divider(color: scheme.outlineVariant, height: 16),
          SelectableText.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: '${sections[i].word} '),
                TextSpan(
                  text: '<<${sections[i].label}>>',
                  style: TextStyle(
                    color: meaningLabelColor(sections[i].label, scheme),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: sections[i].body.contains('\n')
                      ? '\n${sections[i].body}'
                      : ' ${sections[i].body}',
                ),
              ],
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
          content: Text('Không lấy được nghĩa online (mạng hoặc không có).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Giữ nguyên IconButton (không đổi loại widget khi loading) để tránh
    // teardown node semantics giữa chừng → lỗi accessibility_bridge AXTree 107.
    return IconButton(
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.travel_explore),
      tooltip: 'Tra thêm nghĩa online (Nhật: Mazii, Trung: Google Dịch)',
      onPressed: _loading ? null : _fetch,
    );
  }
}
