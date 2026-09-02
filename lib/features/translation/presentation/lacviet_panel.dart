import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/markdown_body_view.dart';
import '../../../shared/widgets/tts_button.dart';
import '../../ai_translation/application/ai_settings_controller.dart';
import '../../ai_translation/domain/ai_lookup_result.dart';
import '../../ai_translation/presentation/ai_lookup_dialog.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../application/lookup_controller.dart';
import '../application/token_selection.dart';
import '../application/translation_controller.dart';
import '../domain/lookup_dictionary_type.dart';
import '../domain/meaning_panel_layout.dart';
import 'online_lookup_dialog.dart';

/// Panel "Nghĩa": header (từ + reading + 🔊 + ✏️) + nội dung tra từ điển.
class LacVietPanel extends ConsumerWidget {
  const LacVietPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(lookupControllerProvider);
    final mode = ref.watch(translationControllerProvider.select((s) => s.mode));
    final isAdmin = ref.watch(
      dictionarySyncProvider.select((state) => state.isAdmin),
    );
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selection = ref.watch(tokenSelectionProvider);
    final popupTypes = ref.watch(
      settingsProvider.select((s) => s.popupDictionaryTypesFor(mode)),
    );
    final hiddenTypes = selection?.origin == TokenSelectionOrigin.source
        ? popupTypes
        : const <LookupDictionaryType>[];
    final layout = ref.watch(
      settingsProvider.select((s) => s.meaningPanelLayoutFor(mode)),
    );
    final visibleSections = orderMeaningSections(
      result?.sections ?? const [],
      layout,
      hiddenTypes,
    );

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
                        Text.rich(
                          TextSpan(
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            children: [
                              if (result.reading != null)
                                TextSpan(text: result.reading!),
                              if (result.reading != null &&
                                  result.hanViet != null)
                                const TextSpan(text: ' · '),
                              if (result.hanViet != null) ...[
                                const TextSpan(text: '('),
                                const TextSpan(
                                  text: 'Hán Việt',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(text: ': ${result.hanViet})'),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                _OnlineLookupButton(
                  color: isDark
                      ? const Color(0xFF4FC3F7)
                      : const Color(0xFF0288D1),
                ),
                _AiLookupButton(
                  color: isDark
                      ? const Color(0xFFCE93D8)
                      : const Color(0xFF8E24AA),
                ),
                TtsButton(
                  textProvider: () => result.matchedKey ?? result.word,
                  mode: mode,
                  tooltip: 'Đọc từ',
                  color: isDark
                      ? const Color(0xFFCE93D8)
                      : const Color(0xFF7B1FA2),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit_note_rounded,
                    color: isDark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE65100),
                  ),
                  tooltip: isAdmin
                      ? 'Sửa trực tiếp trong VietPhrase'
                      : 'Sửa nghĩa trong UserDict',
                  onPressed: () => isAdmin
                      ? showSharedEntryEditDialog(
                          context,
                          ref,
                          word: result.word,
                          kind: SharedDictionaryKind.vietPhrase,
                        )
                      : showEntryEditDialog(
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
              child: visibleSections.isEmpty
                  ? SelectableText(
                      'Không tìm thấy trong từ điển.',
                      style: ref.watch(
                        settingsProvider.select(
                          (s) => s.paneTextStyleFor(PaneId.meaning),
                        ),
                      ),
                    )
                  : _MeaningSections(sections: visibleSections),
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
    case 'Mazii Trung-Việt':
      return const Color(0xFFEF6C00); // orange
    case 'Mazii Online':
      return const Color(0xFF43A047); // light green
    case 'Google Dịch':
      return const Color(0xFF1565C0); // blue
    case 'Jisho':
      return const Color(0xFF00695C); // dark teal
    case 'Weblio 日中':
      return const Color(0xFFAD1457); // dark pink
    case 'Youdao 中英':
      return const Color(0xFF5E35B1); // deep purple
    case 'AI Dịch':
    case 'AI Tra Cứu':
    case 'AI tách từ':
      return const Color(0xFF8E24AA); // purple
    default:
      return scheme.primary;
  }
}

/// Lọc + sắp xếp mục theo bố cục người dùng đặt trong Cài đặt.
///
/// Sắp xếp ỔN ĐỊNH theo vị trí của loại từ điển: nhiều mục cùng loại (VD các
/// nguồn online) giữ nguyên thứ tự `lookup()` sinh ra. Mục có loại lạ (nhãn
/// chưa map được) luôn hiện, xếp cuối — thà thừa còn hơn nuốt mất nghĩa.
List<LookupSection> orderMeaningSections(
  List<LookupSection> sections,
  MeaningPanelLayout layout,
  List<LookupDictionaryType> hiddenByPopup,
) {
  final kept = <(int, int, LookupSection)>[];
  for (var i = 0; i < sections.length; i++) {
    final type = sections[i].dictionaryType;
    if (type != null) {
      if (hiddenByPopup.contains(type)) continue;
      if (!layout.isVisible(type)) continue;
    }
    kept.add((layout.indexOf(type), i, sections[i]));
  }
  kept.sort((a, b) {
    final byType = a.$1.compareTo(b.$1);
    return byType != 0 ? byType : a.$2.compareTo(b.$2);
  });
  return [for (final row in kept) row.$3];
}

/// Chỉ mục AI mới có thân Markdown/JSON; các từ điển offline là text thuần nên
/// giữ nguyên đường render cũ (nhanh hơn, không đụng bố cục đang dùng).
bool _isMarkdown(LookupSection section) =>
    LookupDictionaryType.ai.matchesLabel(section.label);

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
          if (i > 0) Divider(color: scheme.outlineVariant, height: 16),
          if (_isMarkdown(sections[i])) ...[
            // Mục AI: thân là Markdown (mục cũ) hoặc JSON (mục mới) → render
            // thành bố cục thật thay vì hiện nguyên `**`, `###`.
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
                ],
              ),
            ),
            MarkdownBodyView(
              data: aiBodyToMarkdown(sections[i].word, sections[i].body),
              style: style,
            ),
          ] else
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

/// Nút tra online: mở dialog tra song song Mazii + Google Dịch.
/// Ẩn khi từ đã tồn tại trong OnlineDict để chống gọi lặp.
class _OnlineLookupButton extends ConsumerWidget {
  const _OnlineLookupButton({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = ref.watch(
      lookupControllerProvider.select((r) => r?.word ?? ''),
    );
    if (word.isEmpty) return const SizedBox.shrink();

    final dicts = ref.watch(dictionariesProvider).valueOrNull;
    if (dicts != null && dicts.onlineDict.entries.containsKey(word)) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(Icons.travel_explore, color: color),
      tooltip: 'Tra online (theo nguồn đã bật trong Cài đặt)',
      onPressed: () => showOnlineLookupDialog(context, ref, word: word),
    );
  }
}

/// Nút tra AI: mở dialog gọi AI tra cứu và phân tích ngữ pháp.
/// Ẩn khi chưa cấu hình key hoặc từ đã tồn tại trong AiDict.
class _AiLookupButton extends ConsumerWidget {
  const _AiLookupButton({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = ref.watch(
      lookupControllerProvider.select((r) => r?.word ?? ''),
    );
    if (word.isEmpty) return const SizedBox.shrink();

    final aiSettings = ref.watch(aiSettingsControllerProvider).valueOrNull;
    if (aiSettings == null || !aiSettings.hasConfiguredKey) {
      return const SizedBox.shrink();
    }

    final dicts = ref.watch(dictionariesProvider).valueOrNull;
    if (dicts != null && dicts.aiDict.entries.containsKey(word)) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(Icons.auto_awesome, color: color),
      tooltip: 'Tra cứu & Phân tích AI (${aiSettings.activeService.label})',
      onPressed: () => showAiLookupDialog(context, ref, word: word),
    );
  }
}
