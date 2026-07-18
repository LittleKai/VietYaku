import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../domain/token.dart';
import '../domain/translation_engine.dart';

class TranslationState {
  final TranslationMode mode;
  final String sourceText;
  final List<Token> tokens;

  /// Phiên âm Hán Việt toàn văn (tab Hán Việt), cùng lượt dịch với [tokens].
  final List<Token> hanVietTokens;
  final int elapsedMs;

  const TranslationState({
    required this.mode,
    this.sourceText = '',
    this.tokens = const [],
    this.hanVietTokens = const [],
    this.elapsedMs = 0,
  });

  bool get hasResult => tokens.isNotEmpty;

  TranslationState copyWith({
    TranslationMode? mode,
    String? sourceText,
    List<Token>? tokens,
    List<Token>? hanVietTokens,
    int? elapsedMs,
  }) => TranslationState(
    mode: mode ?? this.mode,
    sourceText: sourceText ?? this.sourceText,
    tokens: tokens ?? this.tokens,
    hanVietTokens: hanVietTokens ?? this.hanVietTokens,
    elapsedMs: elapsedMs ?? this.elapsedMs,
  );
}

/// Mode đang dịch — provider riêng để dictionariesProvider watch được
/// mà không tạo vòng phụ thuộc với TranslationController.
class CurrentModeNotifier extends Notifier<TranslationMode> {
  @override
  TranslationMode build() => ref.read(settingsProvider).defaultMode;

  void set(TranslationMode mode) => state = mode;
}

final currentModeProvider =
    NotifierProvider<CurrentModeNotifier, TranslationMode>(
      CurrentModeNotifier.new,
    );

class TranslationController extends Notifier<TranslationState> {
  @override
  TranslationState build() {
    return TranslationState(mode: ref.read(settingsProvider).defaultMode);
  }

  Future<void> setMode(TranslationMode mode) async {
    if (state.mode == mode) return;
    ref.read(currentModeProvider.notifier).set(mode);
    state = state.copyWith(mode: mode);
    if (state.sourceText.isNotEmpty && state.hasResult) {
      // Bộ dict theo mode nạp lại xong mới dịch lại bằng dict mới.
      await ref.read(dictionariesProvider.future);
      translate(state.sourceText);
    }
  }

  /// Dịch [text] bằng engine hiện tại. Không có dict (đang load) → giữ nguyên.
  void translate(String text) {
    final dicts = ref.read(dictionariesProvider).valueOrNull;
    if (dicts == null) return;
    final settings = ref.read(settingsProvider);
    final engine = dicts.engineWith(
      algorithm: settings.translationAlgorithm,
      prioritizeNames: settings.prioritizeNames,
    );
    final sw = Stopwatch()..start();
    final tokens = engine.translate(text, mode: state.mode);
    sw.stop();
    final hanVietTokens = dicts.hanVietEngine.translate(text, mode: state.mode);
    state = state.copyWith(
      sourceText: text,
      tokens: tokens,
      hanVietTokens: hanVietTokens,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// Dán clipboard vào nguồn rồi dịch (nút menu bar; SourcePane đồng bộ
  /// text qua listen sourceText).
  Future<void> pasteAndTranslate() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return;
    translate(text);
  }

  void clear() {
    state = state.copyWith(
      sourceText: '',
      tokens: const [],
      hanVietTokens: const [],
      elapsedMs: 0,
    );
  }
}

final translationControllerProvider =
    NotifierProvider<TranslationController, TranslationState>(
      TranslationController.new,
    );
