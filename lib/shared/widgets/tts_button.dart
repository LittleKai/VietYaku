import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tts_service.dart';
import '../../features/translation/domain/translation_engine.dart';

/// Nút 🔊: disable + tooltip hướng dẫn cài voice khi thiếu voice offline.
class TtsButton extends ConsumerWidget {
  final String Function() textProvider;
  final TranslationMode mode;
  final String tooltip;

  const TtsButton({
    super.key,
    required this.textProvider,
    required this.mode,
    this.tooltip = 'Đọc',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(ttsServiceProvider).valueOrNull;
    final available = tts?.availableFor(mode) ?? false;
    final language = TtsService.languageFor(mode);

    return IconButton(
      icon: const Icon(Icons.volume_up),
      tooltip: available
          ? tooltip
          : 'Chưa có voice $language.\nCài tại Settings > Time & Language > '
              'Speech > Add voices',
      onPressed:
          available ? () => tts!.speak(textProvider(), mode) : null,
    );
  }
}
