import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../features/translation/domain/translation_engine.dart';

/// Bọc flutter_tts (WinRT SpeechSynthesizer, offline).
///
/// Voice thiếu → nút 🔊 disable kèm tooltip hướng dẫn cài
/// (Settings > Time & Language > Speech > Add voices).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  Set<String> _languages = {};

  static String languageFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? 'ja-JP' : 'zh-CN';

  bool availableFor(TranslationMode mode) {
    final prefix = mode == TranslationMode.japanese ? 'ja' : 'zh';
    return _languages.any((l) => l.startsWith(prefix));
  }

  Future<void> init() async {
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) {
        _languages = langs.map((e) => e.toString().toLowerCase()).toSet();
      }
    } catch (e) {
      debugPrint('TTS getLanguages failed: $e');
      _languages = {};
    }
  }

  Future<void> speak(String text, TranslationMode mode) async {
    if (text.trim().isEmpty || !availableFor(mode)) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(languageFor(mode));
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> stop() => _tts.stop();
}

final ttsServiceProvider = FutureProvider<TtsService>((ref) async {
  final service = TtsService();
  await service.init();
  ref.onDispose(service.stop);
  return service;
});
