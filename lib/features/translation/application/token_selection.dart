import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../domain/secondary_phrase.dart';
import '../domain/token.dart';
import 'lookup_controller.dart';
import 'secondary_phrases_provider.dart';
import 'translation_controller.dart';

/// Cụm đang được chọn (nháy chuột) — range theo UTF-16 offset trong văn bản
/// nguồn, dùng chung để tô nổi ở ô Nguồn / Hán Việt / VietPhrase.
class TokenSelection {
  final int start;
  final int end;
  final String word;
  final TokenSelectionOrigin origin;

  const TokenSelection({
    required this.start,
    required this.end,
    required this.word,
    required this.origin,
  });
}

enum TokenSelectionOrigin { source, result }

class TokenSelectionNotifier extends Notifier<TokenSelection?> {
  @override
  TokenSelection? build() {
    // Đổi văn bản nguồn → bỏ chọn (offset cũ không còn đúng).
    ref.watch(translationControllerProvider.select((s) => s.sourceText));
    return null;
  }

  /// Chọn 1 token (từ ô VietPhrase / Hán Việt).
  void selectToken(Token token) {
    if (token.kind == TokenKind.passthrough) return;
    // Kana không match nằm trong cụm từ điển phụ: token đầu cụm → chọn cả cụm;
    // token GIỮA cụm → tra lại cụm bắt đầu từ chính token đó (cùng quy tắc với
    // click ở ô Nguồn). Không có cụm nào bắt đầu ở đó → chọn riêng token.
    final phrase = _secondaryPhraseAt(token.sourceStart);
    if (phrase != null) {
      final state = ref.read(translationControllerProvider);
      final target = phrase.start == token.sourceStart
          ? phrase
          : _secondaryPhraseStartingAt(
              state.sourceText,
              state.tokens,
              token.sourceStart,
            );
      if (target != null) {
        _apply(
          target.start,
          target.end,
          target.source,
          TokenSelectionOrigin.result,
        );
        return;
      }
    }
    _apply(
      token.sourceStart,
      token.sourceStart + token.source.length,
      token.source,
      TokenSelectionOrigin.result,
    );
  }

  /// Chọn theo vị trí caret trong văn bản nguồn → cụm chứa vị trí đó.
  ///
  /// Click ngay đầu token → dùng nguyên token đã ghép. Click GIỮA token
  /// (VD 少女達 ghép thành 1 cụm, click vào 女) → tra lại từ đúng ký tự bị
  /// click, bỏ qua phần đứng trước trong cụm gốc.
  void selectAtSourceOffset(int offset) {
    final state = ref.read(translationControllerProvider);
    // Cụm từ điển phụ (kana không match VietPhrase): click đúng đầu cụm →
    // dùng cả cụm; click GIỮA cụm → tra lại cụm bắt đầu từ ký tự bị click
    // (VD はやめて ghép はや, click や → やめ). Không có cụm nào bắt đầu tại
    // đó thì rơi xuống vòng token bên dưới (chọn đúng ký tự bị click).
    final phrase = _secondaryPhraseAt(offset);
    if (phrase != null) {
      final target = phrase.start == offset
          ? phrase
          : _secondaryPhraseStartingAt(state.sourceText, state.tokens, offset);
      if (target != null) {
        _apply(
          target.start,
          target.end,
          target.source,
          TokenSelectionOrigin.source,
        );
        return;
      }
    }
    for (final t in state.tokens) {
      if (t.kind == TokenKind.passthrough) continue;
      if (offset < t.sourceStart || offset >= t.sourceStart + t.source.length) {
        continue;
      }
      if (offset == t.sourceStart) {
        _apply(
          t.sourceStart,
          t.sourceStart + t.source.length,
          t.source,
          TokenSelectionOrigin.source,
        );
        return;
      }
      final dicts = ref.read(dictionariesProvider).valueOrNull;
      if (dicts == null) {
        _apply(
          t.sourceStart,
          t.sourceStart + t.source.length,
          t.source,
          TokenSelectionOrigin.source,
        );
        return;
      }
      final settings = ref.read(settingsProvider);
      final engine = dicts.engineWith(
        algorithm: settings.translationAlgorithm,
        prioritizeNames: settings.prioritizeNames,
      );
      final match = engine.matchAt(state.sourceText, offset);
      _apply(
        match.sourceStart,
        match.sourceStart + match.source.length,
        match.source,
        TokenSelectionOrigin.source,
      );
      return;
    }
  }

  /// Cụm từ điển phụ chứa [offset] (nếu có).
  SecondaryPhrase? _secondaryPhraseAt(int offset) {
    for (final p in ref.read(secondaryPhrasesProvider)) {
      if (p.contains(offset)) return p;
    }
    return null;
  }

  /// Cụm từ điển phụ bắt đầu đúng tại [offset] (tra lại khi click giữa cụm).
  SecondaryPhrase? _secondaryPhraseStartingAt(
    String text,
    List<Token> tokens,
    int offset,
  ) {
    final dicts = ref.read(dictionariesProvider).valueOrNull;
    if (dicts == null) return null;
    return secondaryPhraseStartingAt(
      text: text,
      tokens: tokens,
      offset: offset,
      lacViet: dicts.lacViet,
      jaVi: dicts.jaVi,
      mazii: dicts.mazii,
      onlineDict: dicts.onlineDict,
      aiDict: dicts.aiDict,
    );
  }

  /// Chọn đúng một khoảng cho trước (bảng "Kiểm tra" bấm vào một cụm chưa
  /// dịch) — không tra lại cụm theo từ điển như [selectAtSourceOffset].
  void selectRange(int start, int end, String word) =>
      _apply(start, end, word, TokenSelectionOrigin.source);

  /// Bỏ active/highlight hiện tại mà không thay đổi nội dung tra cứu đã tải.
  void clear() => state = null;

  void _apply(int start, int end, String word, TokenSelectionOrigin origin) {
    state = TokenSelection(start: start, end: end, word: word, origin: origin);
    final text = ref.read(translationControllerProvider).sourceText;
    ref
        .read(lookupControllerProvider.notifier)
        .lookup(word, rawSentence: _sentenceAt(text, start));
  }

  /// Đoạn nguồn từ vị trí chọn: tối đa 12 rune, dừng ở dấu ngắt câu.
  static String _sentenceAt(String text, int start) {
    if (start < 0 || start >= text.length) return '';
    const enders = {'。', '．', '！', '？', '!', '?', '\n', '\r'};
    var i = start;
    var runes = 0;
    while (i < text.length && runes < 12) {
      final len = runeLengthAt(text, i);
      if (enders.contains(text.substring(i, i + len))) break;
      i += len;
      runes++;
    }
    return text.substring(start, i).trim();
  }
}

final tokenSelectionProvider =
    NotifierProvider<TokenSelectionNotifier, TokenSelection?>(
      TokenSelectionNotifier.new,
    );
