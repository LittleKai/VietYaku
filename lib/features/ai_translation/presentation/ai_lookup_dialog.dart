import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/markdown_body_view.dart';
import '../application/ai_lookup_controller.dart';
import '../application/ai_settings_controller.dart';
import '../data/ai_api_client.dart';
import '../domain/ai_lookup_result.dart';
import '../domain/ai_service_config.dart';
import 'ai_settings_dialog.dart';

Future<void> showAiLookupDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
}) {
  final aiSettings =
      ref.read(aiSettingsControllerProvider).valueOrNull ??
      AiSettings.defaults();
  final service = aiSettings.activeService;
  final model = aiSettings.activeConfig.selectedModel;

  return showAppDialog<void>(
    context: context,
    icon: Icons.auto_awesome,
    title: 'Tra cứu & Phân tích AI: $word',
    description: '${service.label} ($model) tra cứu nghĩa và phân tích ngữ pháp, từ tố.',
    accentColor: const Color(0xFF8E24AA),
    width: 600,
    content: _AiLookupContent(word: word),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Đóng'),
      ),
    ],
  );
}

class _AiLookupContent extends ConsumerStatefulWidget {
  const _AiLookupContent({required this.word});

  final String word;

  @override
  ConsumerState<_AiLookupContent> createState() => _AiLookupContentState();
}

class _AiLookupContentState extends ConsumerState<_AiLookupContent> {
  late Future<AiApiResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = executeAiLookup(ref, widget.word);
  }

  void _retry() {
    setState(() {
      _future = executeAiLookup(ref, widget.word);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<AiApiResponse>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 3),
                const SizedBox(height: 16),
                Text(
                  'AI đang tra cứu và phân tích ngữ pháp cho "${widget.word}"...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final response = snapshot.data;
        if (response == null || !response.isSuccess) {
          final errorMsg = response?.error ?? 'Không thể kết nối tới dịch vụ AI.';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.error),
                    const SizedBox(width: 8),
                    Text(
                      'Lỗi tra cứu AI',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(errorMsg, style: TextStyle(color: scheme.onErrorContainer)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Thử lại'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        // Lấy context của Navigator TRƯỚC khi pop: sau pop thì
                        // context của dialog không tra ngược cây widget được
                        // nữa.
                        final navigator = Navigator.of(context);
                        final hostContext = navigator.context;
                        navigator.pop();
                        showAiSettingsDialog(hostContext, ref);
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Mở cài đặt AI'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8E24AA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '<<AI Dịch>> (Đã lưu vào từ điển)',
                    style: TextStyle(
                      color: Color(0xFF8E24AA),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                MarkdownBodyView(
                  // AI trả JSON → render theo bố cục của app; model không chịu
                  // trả JSON thì rơi về Markdown nguyên văn.
                  data:
                      AiLookupResult.tryParse(
                        widget.word,
                        response.text!,
                      )?.toMarkdown() ??
                      response.text!,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(height: 1.5) ??
                      const TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
