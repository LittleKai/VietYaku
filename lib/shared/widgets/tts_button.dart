import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tts_service.dart';
import '../../features/settings/settings_provider.dart';
import '../../features/translation/domain/translation_engine.dart';

/// Nút 🔊: disable + tooltip hướng dẫn cài voice khi thiếu voice offline.
class TtsButton extends ConsumerWidget {
  final String Function() textProvider;
  final TranslationMode mode;
  final String tooltip;
  final Color? color;

  const TtsButton({
    super.key,
    required this.textProvider,
    required this.mode,
    this.tooltip = 'Đọc',
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(ttsServiceProvider).valueOrNull;
    final available = tts?.availableFor(mode) ?? false;
    final language = TtsService.languageFor(mode);

    return IconButton(
      icon: Icon(Icons.volume_up, color: available ? color : null),
      tooltip: available
          ? tooltip
          : 'Chưa có voice $language.\nCài tại Settings > Time & Language > '
                'Speech > Add voices',
      onPressed: available
          ? () {
              final settings = ref.read(settingsProvider);
              tts!.speak(
                textProvider(),
                mode,
                voiceKey: settings.ttsVoiceFor(mode),
                rate: settings.ttsSpeechRateFor(mode),
              );
            }
          : null,
    );
  }
}
