import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../domain/token.dart';
import '../domain/translation_engine.dart';

class TranslationState {
  final TranslationMode mode;
  final String sourceText;
  final List<Token> tokens;
  final int elapsedMs;

  const TranslationState({
    required this.mode,
    this.sourceText = '',
    this.tokens = const [],
    this.elapsedMs = 0,
  });

  bool get hasResult => tokens.isNotEmpty;

  TranslationState copyWith({
    TranslationMode? mode,
    String? sourceText,
    List<Token>? tokens,
    int? elapsedMs,
  }) =>
      TranslationState(
        mode: mode ?? this.mode,
        sourceText: sourceText ?? this.sourceText,
        tokens: tokens ?? this.tokens,
        elapsedMs: elapsedMs ?? this.elapsedMs,
      );
}

class TranslationController extends Notifier<TranslationState> {
  @override
  TranslationState build() {
    return TranslationState(mode: ref.read(settingsProvider).defaultMode);
  }

  void setMode(TranslationMode mode) {
    state = state.copyWith(mode: mode);
    if (state.sourceText.isNotEmpty && state.hasResult) {
      translate(state.sourceText);
    }
  }

  /// Dịch [text] bằng engine hiện tại. Không có dict (đang load) → giữ nguyên.
  void translate(String text) {
    final dicts = ref.read(dictionariesProvider).valueOrNull;
    if (dicts == null) return;
    final sw = Stopwatch()..start();
    final tokens = dicts.engine.translate(text, mode: state.mode);
    sw.stop();
    state = state.copyWith(
      sourceText: text,
      tokens: tokens,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  void clear() {
    state = state.copyWith(sourceText: '', tokens: const [], elapsedMs: 0);
  }
}

final translationControllerProvider =
    NotifierProvider<TranslationController, TranslationState>(
        TranslationController.new);
