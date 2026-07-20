import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../domain/token.dart';
import 'lookup_controller.dart';
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

  /// Chọn 1 token (từ ô kết quả / Hán Việt).
  void selectToken(Token token) {
    if (token.kind == TokenKind.passthrough) return;
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

  /// Bỏ active/highlight hiện tại mà không thay đổi nội dung tra cứu đã tải.
  void clear() => state = null;

  void _apply(int start, int end, String word, TokenSelectionOrigin origin) {
    state = TokenSelection(start: start, end: end, word: word, origin: origin);
    final text = ref.read(translationControllerProvider).sourceText;
    ref
        .read(lookupControllerProvider.notifier)
        .lookup(word, sentence: _sentenceAt(text, start));
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
