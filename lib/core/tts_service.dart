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

  /// Voice mặc định (đầu tiên) mỗi ngôn ngữ — cache từ getVoices.
  final Map<String, Map<String, String>> _voiceByPrefix = {};

  /// Tất cả voice cài đặt theo ngôn ngữ (`{'name','locale'}`), cho UI chọn.
  final Map<String, List<Map<String, String>>> _allVoicesByPrefix = {
    'ja': [],
    'zh': [],
  };

  static String languageFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? 'ja-JP' : 'zh-CN';

  static String _prefixFor(TranslationMode mode) =>
      mode == TranslationMode.japanese ? 'ja' : 'zh';

  /// Khoá định danh voice để lưu/so khớp: `"name::locale"`.
  static String voiceKeyOf(Map<String, String> voice) =>
      '${voice['name']}::${voice['locale']}';

  /// Danh sách voice cài đặt cho [mode] (rỗng nếu chưa có).
  List<Map<String, String>> voicesFor(TranslationMode mode) =>
      _allVoicesByPrefix[_prefixFor(mode)] ?? const [];

  bool availableFor(TranslationMode mode) {
    final prefix = _prefixFor(mode);
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
    // Chọn sẵn voice cho ja/zh để speak không đọc nhầm âm ngôn ngữ khác
    // (WinRT: setLanguage đơn thuần đôi khi giữ voice cũ → kanji đọc kiểu Trung).
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          if (v is! Map) continue;
          final name = v['name']?.toString();
          final locale = v['locale']?.toString();
          if (name == null || locale == null) continue;
          final lower = locale.toLowerCase();
          for (final prefix in const ['ja', 'zh']) {
            if (lower.startsWith(prefix)) {
              _allVoicesByPrefix[prefix]!.add({'name': name, 'locale': locale});
              _voiceByPrefix.putIfAbsent(
                prefix,
                () => {'name': name, 'locale': locale},
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('TTS getVoices failed: $e');
    }
  }

  /// Đọc [text] theo [mode]. [voiceKey] (`"name::locale"`) chọn voice cụ thể —
  /// rỗng/không khớp thì tự động dùng voice đầu tiên. [rate] 0.1–1.0.
  Future<void> speak(
    String text,
    TranslationMode mode, {
    String? voiceKey,
    double? rate,
  }) async {
    if (text.trim().isEmpty || !availableFor(mode)) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(languageFor(mode));
      if (rate != null) await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
      final voice = _resolveVoice(mode, voiceKey);
      if (voice != null) await _tts.setVoice(voice);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  /// Voice khớp [voiceKey] trong danh sách của [mode]; fallback voice mặc định.
  Map<String, String>? _resolveVoice(TranslationMode mode, String? voiceKey) {
    final prefix = _prefixFor(mode);
    if (voiceKey != null && voiceKey.isNotEmpty) {
      for (final v in _allVoicesByPrefix[prefix] ?? const []) {
        if (voiceKeyOf(v) == voiceKey) return v;
      }
    }
    return _voiceByPrefix[prefix];
  }

  Future<void> stop() => _tts.stop();
}

final ttsServiceProvider = FutureProvider<TtsService>((ref) async {
  final service = TtsService();
  await service.init();
  ref.onDispose(service.stop);
  return service;
});
