import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/icon_context_menu.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/domain/dict_type.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../application/lookup_controller.dart';
import '../application/secondary_phrases_provider.dart';
import '../application/token_selection.dart';
import '../application/viet_draft.dart';
import '../domain/secondary_phrase.dart';
import '../domain/token.dart';
import '../domain/vietphrase_value.dart';
import 'lacviet_panel.dart' show meaningLabelColor;
import 'online_lookup_dialog.dart';

/// Một token đã tính text hiển thị (đã chuẩn hoá + viết hoa).
typedef _Piece = ({Token token, String text});

/// Cụm từ điển phụ chứa vị trí nguồn của [token] (nếu có).
SecondaryPhrase? _secondaryPhraseAt(
  List<SecondaryPhrase> phrases,
  Token token,
) {
  for (final p in phrases) {
    if (p.contains(token.sourceStart)) return p;
  }
  return null;
}

/// Danh sách token dạng SelectableText: nháy chuột vào chữ (kiểu caret trong
/// edittext) → chọn cụm tại vị trí đó, tô nổi đỏ đồng bộ mọi pane + tra Nghĩa.
/// Chuột phải KHÔNG tô đen → paste nghĩa dưới con trỏ vào ô Bản dịch
/// (ô VietPhrase). Chuột phải khi tô đen → menu Thêm/Sửa VietPhrase /
/// Lạc Việt / Names. [textOf] quyết định văn bản hiển thị (display /
/// displayAll).
class TokenTextView extends ConsumerStatefulWidget {
  const TokenTextView({
    super.key,
    required this.tokens,
    required this.textOf,
    required this.paneId,
  });

  final List<Token> tokens;
  final String Function(Token) textOf;
  final PaneId paneId;

  @override
  ConsumerState<TokenTextView> createState() => _TokenTextViewState();

  /// Dấu đóng/kết câu → KHÔNG chèn space phía trước.
  static const _closePunct = {
    ',',
    '.',
    '!',
    '?',
    ':',
    ';',
    ')',
    ']',
    '}',
    '…',
    '%',
    '』',
    '〉',
    '》',
    '〞',
    '〟',
    '﹄',
  };

  /// Dấu mở → KHÔNG chèn space phía sau.
  static const _openPunct = {'(', '[', '{', '『', '〈', '《', '〝', '﹃'};

  /// Có cần 1 space giữa hai đoạn text liền kề khi render/copy.
  static bool _needSpaceBetween(String cur, String next) {
    if (cur.isEmpty || next.isEmpty) return false;
    final lastCur = cur[cur.length - 1];
    final firstNext = next[0];
    if (lastCur == ' ' || lastCur == '\n' || lastCur == '\t') return false;
    if (firstNext == ' ' || firstNext == '\n' || firstNext == '\t') {
      return false;
    }
    if (_closePunct.contains(firstNext)) return false;
    if (_openPunct.contains(lastCur)) return false;
    return true;
  }

  /// Dấu cần 1 space phía sau (khi ký tự kế là chữ/CJK).
  static const _spaceAfterPunct = {',', '.', '!', '?', ';', ':'};

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }

  /// Chèn space sau dấu câu bên trong một đoạn (vd ",AAH" → ", AAH"), trừ khi
  /// ký tự sau là space/số/dấu khác (giữ nguyên "3.14", "1,000").
  static String _spacePunctuation(String s) {
    final sb = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      sb.write(c);
      if (_spaceAfterPunct.contains(c) && i + 1 < s.length) {
        final next = s[i + 1];
        final glued =
            next == ' ' ||
            next == '\n' ||
            next == '\t' ||
            _isDigit(next) ||
            _spaceAfterPunct.contains(next) ||
            _closePunct.contains(next);
        if (!glued) sb.write(' ');
      }
    }
    return sb.toString();
  }

  /// Text hiển thị của 1 token: passthrough được chuẩn hoá dấu câu/toàn-hình
  /// và chèn space sau dấu câu.
  static String _displayText(
    Token token,
    String Function(Token) textOf,
    bool keepSpecialQuotes,
  ) {
    final text = textOf(token);
    if (token.kind == TokenKind.passthrough) {
      return _spacePunctuation(
        normalizeDisplayText(text, keepSpecialQuotes: keepSpecialQuotes),
      );
    }
    return text;
  }

  /// Các "mảnh" hiển thị của một đoạn: bỏ token có nghĩa rỗng (vd 的 bị lọc)
  /// để không tạo khoảng trống thừa, rồi viết hoa sau dấu kết câu.
  static List<_Piece> _pieces(
    List<Token> paragraph,
    String Function(Token) textOf, {
    bool keepSpecialQuotes = true,
  }) {
    final pieces = <_Piece>[];
    for (final token in paragraph) {
      final text = _displayText(token, textOf, keepSpecialQuotes);
      if (token.kind != TokenKind.passthrough && text.trim().isEmpty) {
        continue; // token bị lọc → bỏ hẳn
      }
      pieces.add((token: token, text: text));
    }
    for (var i = 0; i < pieces.length; i++) {
      if (_shouldCapitalize(pieces, i)) {
        pieces[i] = (token: pieces[i].token, text: _capitalize(pieces[i].text));
      }
    }
    return pieces;
  }

  /// Ghép text thuần từ [tokens] theo cùng quy tắc render (dùng cho nút copy).
  static String plainText(
    List<Token> tokens,
    String Function(Token) textOf, {
    bool keepSpecialQuotes = true,
  }) {
    return paragraphs(tokens)
        .map((p) {
          final pieces = _pieces(
            p,
            textOf,
            keepSpecialQuotes: keepSpecialQuotes,
          );
          final sb = StringBuffer();
          for (var i = 0; i < pieces.length; i++) {
            sb.write(pieces[i].text);
            if (i + 1 < pieces.length &&
                _needSpaceBetween(pieces[i].text, pieces[i + 1].text)) {
              sb.write(' ');
            }
          }
          return sb.toString().trimRight();
        })
        .join('\n');
  }

  /// Tách token thành các đoạn theo newline trong passthrough.
  static List<List<Token>> paragraphs(List<Token> tokens) {
    final paragraphs = <List<Token>>[[]];
    for (final token in tokens) {
      if (token.kind == TokenKind.passthrough && token.source.contains('\n')) {
        final parts = token.source.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) paragraphs.add([]);
          final text = parts[i].replaceAll('\r', '');
          if (text.isNotEmpty) {
            paragraphs.last.add(
              Token(
                source: text,
                sourceStart: token.sourceStart,
                kind: TokenKind.passthrough,
              ),
            );
          }
        }
      } else {
        paragraphs.last.add(token);
      }
    }
    paragraphs.removeWhere((p) => p.isEmpty);
    return paragraphs;
  }

  /// Ký tự kết câu (ASCII + toàn-hình CJK) → chữ Việt kế tiếp viết hoa.
  static const _sentenceEnders = {'.', '!', '?', '…', '。', '．', '！', '？', '⋯'};

  /// Nháy/ngoặc mở "trong suốt" khi xét viết hoa: `" [hành/đi]` đầu hàng
  /// hoặc sau dấu kết câu vẫn viết hoa chữ cái đầu.
  static const _capitalizeTransparent = {
    '"',
    "'",
    '(',
    '[',
    '{',
    '«',
    '“',
    '‘',
    '『',
    '〈',
    '《',
    '〝',
    '﹃',
  };

  static bool _shouldCapitalize(List<_Piece> pieces, int index) {
    if (index == 0) return true;
    for (var j = index - 1; j >= 0; j--) {
      var prevText = pieces[j].text.trim();
      // Bỏ nháy/ngoặc mở ở cuối (vd `"` hay `. "`) — không chặn viết hoa.
      while (prevText.isNotEmpty &&
          _capitalizeTransparent.contains(prevText[prevText.length - 1])) {
        prevText = prevText.substring(0, prevText.length - 1).trimRight();
      }
      if (prevText.isEmpty) continue;
      final lastChar = prevText[prevText.length - 1];
      return _sentenceEnders.contains(lastChar);
    }
    // Phía trước chỉ toàn nháy/ngoặc mở → coi như đầu hàng.
    return true;
  }

  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    var startIdx = 0;
    while (startIdx < text.length &&
        (_capitalizeTransparent.contains(text[startIdx]) ||
            RegExp(r'[\s①-⑳]').hasMatch(text[startIdx]))) {
      if (text[startIdx] == '(' &&
          RegExp(r'^\([a-zA-Z]+\)\s*').hasMatch(text.substring(startIdx))) {
        break;
      }
      startIdx++;
    }
    final remaining = text.substring(startIdx);
    final posMatch = RegExp(r'^\([a-zA-Z]+\)\s*').firstMatch(remaining);
    if (posMatch != null) {
      startIdx += posMatch.end;
    }
    for (var i = startIdx; i < text.length; i++) {
      final char = text[i];
      if (RegExp(r'[a-zA-ZÀ-ỹÀ-Ỹ]').hasMatch(char)) {
        return text.substring(0, i) +
            char.toUpperCase() +
            text.substring(i + 1);
      }
      if (RegExp(r'[0-9]').hasMatch(char)) break;
    }
    return text;
  }

  static bool _hasCapitalAtStart(String text) {
    if (text.isEmpty) return false;
    var startIdx = 0;
    while (startIdx < text.length &&
        (_capitalizeTransparent.contains(text[startIdx]) ||
            RegExp(r'[\s①-⑳]').hasMatch(text[startIdx]))) {
      if (text[startIdx] == '(' &&
          RegExp(r'^\([a-zA-Z]+\)\s*').hasMatch(text.substring(startIdx))) {
        break;
      }
      startIdx++;
    }
    final remaining = text.substring(startIdx);
    final posMatch = RegExp(r'^\([a-zA-Z]+\)\s*').firstMatch(remaining);
    if (posMatch != null) {
      startIdx += posMatch.end;
    }
    for (var i = startIdx; i < text.length; i++) {
      final char = text[i];
      if (RegExp(r'[a-zA-ZÀ-ỹÀ-Ỹ]').hasMatch(char)) {
        return char == char.toUpperCase() && char != char.toLowerCase();
      }
    }
    return false;
  }
}

/// Key từ điển của vùng bôi đen ở ô kết quả: nối `source` của MỌI token
/// không-passthrough nằm trong khoảng từ token đầu tới token cuối được chọn.
///
/// Token có nghĩa rỗng (VD `了=` trong VietPhrase) bị bỏ khỏi phần hiển thị nên
/// không bao giờ nằm trong vùng chọn, nhưng vẫn thuộc văn bản nguồn — bôi đen
/// "kích động ra hỏa khí" phải cho key `激出了火气`, không phải `激出火气`.
String selectionSourceKey(List<Token> paragraph, List<Token> selected) {
  if (selected.isEmpty) return '';
  final start = selected.first.sourceStart;
  final last = selected.last;
  final end = last.sourceStart + last.source.length;
  final sb = StringBuffer();
  for (final token in paragraph) {
    if (token.kind == TokenKind.passthrough) continue;
    if (token.sourceStart < start || token.sourceStart >= end) continue;
    sb.write(token.source);
  }
  return sb.toString();
}

/// Viết hoa chữ cái đầu của mỗi từ (tách theo khoảng trắng). Dùng để tạo
/// nghĩa mặc định khi thêm tên riêng vào Names.
String _capitalizeWords(String text) {
  return text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

class _TokenTextViewState extends ConsumerState<TokenTextView> {
  /// Vị trí global của lần nhấn chuột phải gần nhất. Trên Windows,
  /// SelectableText đã có focus thì chuột phải KHÔNG dời caret/selection
  /// (text_selection.dart onSecondaryTap) → không dùng selection để biết
  /// từ nào bị nhấn; map điểm nhấn qua renderEditable.getPositionForPoint.
  Offset? _secondaryTapPosition;
  bool _ignoreCollapsedSelection = false;

  TextStyle _styleFor(
    Token token,
    ColorScheme scheme,
    AppSemanticColors sem,
    TokenSelection? selection,
    Color katakanaColor,
  ) {
    if (selection != null &&
        token.kind != TokenKind.passthrough &&
        token.sourceStart < selection.end &&
        selection.start < token.sourceStart + token.source.length) {
      return TextStyle(color: sem.highlight, fontWeight: FontWeight.bold);
    }
    switch (token.kind) {
      case TokenKind.matched:
        switch (token.dictType) {
          case DictType.userDict:
            return TextStyle(
              color: scheme.tertiary,
              fontWeight: FontWeight.w600,
            );
          case DictType.names:
            return TextStyle(color: sem.nameToken, fontWeight: FontWeight.w600);
          default:
            return TextStyle(color: scheme.onSurface);
        }
      case TokenKind.hanViet:
        return TextStyle(color: scheme.primary, fontStyle: FontStyle.italic);
      case TokenKind.unmatched:
        // Katakana/furigana (kana không match) — màu do user chọn.
        return TextStyle(color: katakanaColor);
      case TokenKind.passthrough:
        return TextStyle(color: scheme.onSurfaceVariant);
    }
  }

  /// Nghĩa tại vị trí [rel] trong text hiển thị của token: chế độ đa nghĩa
  /// "[a/b/c]", "[① A ‖ ② B]", "[A ²]" → lấy đúng nghĩa dưới con trỏ; một nghĩa → cả text.
  static String _meaningAt(String text, int rel) {
    if (text.isEmpty) return '';
    const delimiters = {'/', '‖', '|'};
    var start = 0;
    var end = text.length;
    for (var i = 0; i < text.length; i++) {
      if (!delimiters.contains(text[i])) continue;
      if (i < rel) {
        start = i + 1;
      } else {
        end = i;
        break;
      }
    }
    var piece = text.substring(start, end);
    return piece
        .replaceAll(RegExp(r'^[\[\(\s①-⑳\d\.]+'), '')
        .replaceAll(RegExp(r'\[[A-Za-zÀ-ỹ]+\]\s*'), '')
        .replaceAll(RegExp(r'\([A-Za-z]+\)\s*'), '')
        .replaceAll(RegExp(r'[⁰¹²³⁴⁵⁶⁷⁸⁹⁺]+'), '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .trim();
  }

  static Color _tierAccentColor(int index, ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    switch (index % 5) {
      case 0:
        return scheme.primary;
      case 1:
        return isDark ? const Color(0xFF26A69A) : const Color(0xFF00897B); // Teal / Emerald
      case 2:
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100); // Amber / Orange
      case 3:
        return isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2); // Purple / Violet
      case 4:
        return isDark ? const Color(0xFFF48FB1) : const Color(0xFFC2185B); // Rose
      default:
        return scheme.primary;
    }
  }

  InlineSpan _buildTokenSpan({
    required Token token,
    required String text,
    required TextStyle baseStyle,
    required ColorScheme scheme,
    required AppSemanticColors sem,
    required bool isSelected,
    required MultiMeaningDisplayMode multiMeaningMode,
  }) {
    if (token.kind != TokenKind.matched ||
        token.rawValue == null ||
        widget.paneId != PaneId.vietPhrase) {
      return TextSpan(text: text, style: baseStyle);
    }

    final raw = token.rawValue!;
    final meanings = parseVietPhraseValue(raw);
    if (meanings.isEmpty) return TextSpan(text: text, style: baseStyle);

    final totalAlternatives = meanings.fold<int>(
      0,
      (count, meaning) => count + meaning.alternatives.length,
    );

    if (multiMeaningMode == MultiMeaningDisplayMode.classic) {
      return TextSpan(text: text, style: baseStyle);
    }

    final hasBracket = text.startsWith('[') && text.endsWith(']');
    if (!hasBracket && totalAlternatives <= 1) {
      if (meanings.first.partOfSpeech != VietPhrasePartOfSpeech.none) {
        final posLabel = '(${meanings.first.partOfSpeech.code}) ';
        if (text.startsWith(posLabel)) {
          final rest = text.substring(posLabel.length);
          final posColor = isSelected ? sem.highlight : scheme.primary;
          return TextSpan(
            style: baseStyle,
            children: [
              TextSpan(
                text: posLabel,
                style: baseStyle.copyWith(
                  color: posColor,
                  fontSize: (baseStyle.fontSize ?? 14) * 0.75,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              TextSpan(text: rest),
            ],
          );
        }
      }
      return TextSpan(text: text, style: baseStyle);
    }

    final bracketColor = isSelected
        ? sem.highlight.withValues(alpha: 0.55)
        : scheme.onSurfaceVariant.withValues(alpha: 0.55);
    final bracketStyle = baseStyle.copyWith(
      color: bracketColor,
      fontWeight: FontWeight.normal,
    );

    final shouldCapitalize = TokenTextView._hasCapitalAtStart(text);
    final innerSpans = <InlineSpan>[];

    switch (multiMeaningMode) {
      case MultiMeaningDisplayMode.visualHierarchy:
        for (var meaningIdx = 0; meaningIdx < meanings.length; meaningIdx++) {
          final meaning = meanings[meaningIdx];
          final isFirstTier = meaningIdx == 0;
          final tierAccent = _tierAccentColor(meaningIdx, scheme);

          // Tầng 1: màu chuẩn (hoặc đỏ khi active)
          // Tầng 2 trở đi: MÀU SẮC RIÊNG BIỆT (Teal, Amber, Purple...) cả khi active lẫn inactive
          final tierColor = isSelected
              ? (isFirstTier ? sem.highlight : tierAccent)
              : (isFirstTier
                  ? (baseStyle.color ?? scheme.onSurface)
                  : tierAccent);

          final tierWeight = isSelected
              ? (isFirstTier ? FontWeight.bold : FontWeight.w600)
              : (baseStyle.fontWeight ?? FontWeight.normal);

          // 1. Nhãn từ loại kiểu mũ: (n), (v)...
          if (meaning.partOfSpeech != VietPhrasePartOfSpeech.none) {
            final posTag = '(${meaning.partOfSpeech.code}) ';
            final posColor = isSelected
                ? (isFirstTier ? sem.highlight : tierAccent)
                : (isFirstTier ? scheme.primary : tierAccent);

            innerSpans.add(
              TextSpan(
                text: posTag,
                style: baseStyle.copyWith(
                  color: posColor,
                  fontSize: (baseStyle.fontSize ?? 14) * 0.75,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            );
          }

          // 2. Các biến thể trong tầng nghĩa này
          for (var altIdx = 0; altIdx < meaning.alternatives.length; altIdx++) {
            final rawAlt = meaning.alternatives[altIdx];
            final altText = (isFirstTier && altIdx == 0 && shouldCapitalize)
                ? TokenTextView._capitalize(rawAlt)
                : rawAlt;

            innerSpans.add(
              TextSpan(
                text: altText,
                style: baseStyle.copyWith(
                  color: tierColor,
                  fontWeight: tierWeight,
                ),
              ),
            );

            if (altIdx + 1 < meaning.alternatives.length) {
              innerSpans.add(
                TextSpan(
                  text: '/',
                  style: baseStyle.copyWith(
                    color: isSelected
                        ? sem.highlight.withValues(alpha: 0.45)
                        : scheme.outlineVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              );
            }
          }

          // Dấu gạch chéo ngăn giữa các tầng nghĩa
          if (meaningIdx + 1 < meanings.length) {
            innerSpans.add(
              TextSpan(
                text: '/',
                style: baseStyle.copyWith(
                  color: isSelected
                      ? sem.highlight.withValues(alpha: 0.45)
                      : scheme.outlineVariant.withValues(alpha: 0.8),
                  fontWeight: FontWeight.normal,
                ),
              ),
            );
          }
        }
        break;

      case MultiMeaningDisplayMode.tieredNumbered:
        final hasMultipleTiers = meanings.length >= 2;
        for (var meaningIdx = 0; meaningIdx < meanings.length; meaningIdx++) {
          final meaning = meanings[meaningIdx];
          final isFirstTier = meaningIdx == 0;
          final tierAccent = _tierAccentColor(meaningIdx, scheme);

          final tierColor = isSelected
              ? (isFirstTier ? sem.highlight : tierAccent)
              : (isFirstTier
                  ? (baseStyle.color ?? scheme.onSurface)
                  : tierAccent);

          final tierWeight = isSelected
              ? (isFirstTier ? FontWeight.bold : FontWeight.w600)
              : (baseStyle.fontWeight ?? FontWeight.normal);

          // 1. Ký hiệu số phân tầng ①, ②... (nếu từ có >= 2 tầng nghĩa)
          if (hasMultipleTiers) {
            final numCircle = '${circledNumber(meaningIdx + 1)} ';
            innerSpans.add(
              TextSpan(
                text: numCircle,
                style: baseStyle.copyWith(
                  color: isSelected && isFirstTier ? sem.highlight : tierAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          // 2. Nhãn từ loại kiểu mũ: (n), (v)...
          if (meaning.partOfSpeech != VietPhrasePartOfSpeech.none) {
            final posTag = '(${meaning.partOfSpeech.code}) ';
            innerSpans.add(
              TextSpan(
                text: posTag,
                style: baseStyle.copyWith(
                  color: isSelected && isFirstTier
                      ? sem.highlight
                      : tierAccent.withValues(alpha: 0.95),
                  fontSize: (baseStyle.fontSize ?? 14) * 0.75,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            );
          }

          // 3. Các biến thể trong tầng này
          for (var altIdx = 0; altIdx < meaning.alternatives.length; altIdx++) {
            final rawAlt = meaning.alternatives[altIdx];
            final altText = (isFirstTier && altIdx == 0 && shouldCapitalize)
                ? TokenTextView._capitalize(rawAlt)
                : rawAlt;

            innerSpans.add(
              TextSpan(
                text: altText,
                style: baseStyle.copyWith(
                  color: tierColor,
                  fontWeight: tierWeight,
                ),
              ),
            );

            if (altIdx + 1 < meaning.alternatives.length) {
              innerSpans.add(
                TextSpan(
                  text: '/',
                  style: baseStyle.copyWith(
                    color: isSelected
                        ? sem.highlight.withValues(alpha: 0.45)
                        : scheme.outlineVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              );
            }
          }

          // Dấu phân cách phân tầng ‖
          if (meaningIdx + 1 < meanings.length) {
            innerSpans.add(
              TextSpan(
                text: ' ‖ ',
                style: baseStyle.copyWith(
                  color: isSelected
                      ? sem.highlight.withValues(alpha: 0.5)
                      : scheme.outline.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }
        }
        break;

      case MultiMeaningDisplayMode.classic:
        final inner = hasBracket ? text.substring(1, text.length - 1) : text;
        innerSpans.add(TextSpan(text: inner, style: baseStyle));
        break;
    }

    if (hasBracket) {
      return TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '[', style: bracketStyle),
          ...innerSpans,
          TextSpan(text: ']', style: bracketStyle),
        ],
      );
    } else {
      return TextSpan(style: baseStyle, children: innerSpans);
    }
  }

  Widget _contextMenu(
    EditableTextState editableTextState,
    List<(int, int, Token)> ranges,
    List<Token> paragraph,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ignoreCollapsedSelection = false;
    });
    final value = editableTextState.textEditingValue;
    final sel = value.selection;

    // Bỏ "Select All" khỏi menu mặc định (giữ Copy…).
    final items = editableTextState.contextMenuButtonItems
        .where((item) => item.type != ContextMenuButtonType.selectAll)
        .toList();

    if (!sel.isValid || sel.isCollapsed) {
      if (widget.paneId != PaneId.vietPhrase) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      }
      // Không tô đen trong ô VietPhrase: chuột phải vào CỤM CÓ TRONG TỪ ĐIỂN
      // (matched) → paste nghĩa dưới con trỏ vào ô Bản dịch; chữ ngoài cụm /
      // hán-kanji ngoài từ điển → không làm gì. Không hiện menu.
      // TIÊU THỤ vị trí nhấn: toolbar có thể rebuild nhiều lần khi đang hiện
      // (selectToken/insert gây rebuild) — nếu không tiêu thụ sẽ paste lặp.
      final tapPos = _secondaryTapPosition;
      _secondaryTapPosition = null;
      Token? hitToken;
      var meaning = '';
      if (tapPos != null) {
        final tapOffset = editableTextState.renderEditable
            .getPositionForPoint(tapPos)
            .offset;
        for (final (start, end, token) in ranges) {
          if (tapOffset >= start &&
              tapOffset < end &&
              token.kind == TokenKind.matched) {
            hitToken = token;
            meaning = _meaningAt(
              value.text.substring(start, end),
              tapOffset - start,
            );
            break;
          }
        }
      }
      // Luôn ẩn toolbar (kể cả khi không paste) — nếu để "đang hiện",
      // lần chuột phải sau bị toggleToolbar nuốt mất, paste lúc được lúc
      // không. Đổi controller phải chờ hết frame (đang build overlay).
      final token = hitToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editableTextState.hideToolbar();
        if (token != null) {
          ref.read(tokenSelectionProvider.notifier).clear();
          insertIntoVietDraft(ref.read(vietDraftControllerProvider), meaning);
        }
      });
      return const SizedBox.shrink();
    }

    // Tô đen → key từ điển là source CJK của các token nằm trong vùng chọn
    // (text hiển thị là nghĩa tiếng Việt, không phải key tra được).
    final selectedTokens = [
      for (final (start, end, token) in ranges)
        if (start < sel.end && sel.start < end) token,
    ];
    final key = selectionSourceKey(paragraph, selectedTokens);
    final word = key.isNotEmpty ? key : sel.textInside(value.text).trim();
    if (word.isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: items,
      );
    }

    final dicts = ref.read(dictionariesProvider).valueOrNull;
    final userMeaning = dicts?.userDict.entries[word];
    final vpMeaning = dicts?.vietPhrase.entries[word];
    final lacVietMeaning = dicts?.lacViet.entries[word];
    final namesMeaning = dicts?.names.entries[word];
    // Prefill nghĩa Names khi thêm mới: âm Hán-Việt từng token, viết hoa
    // chữ đầu mỗi từ (VD 田中 → "Điền Trung").
    final defaultNamesMeaning = _capitalizeWords(
      selectedTokens.map((t) => t.display).join(' '),
    );
    String verb(bool exists) => exists ? 'Sửa' : 'Thêm';

    final isAdmin = ref.read(dictionarySyncProvider).isAdmin;
    final scheme = Theme.of(context).colorScheme;
    final custom = <IconContextMenuItem>[];
    if (isAdmin) {
      custom.addAll([
        IconContextMenuItem(
          icon: Icons.menu_book_outlined,
          iconColor: meaningLabelColor('VietPhrase', scheme),
          label: '${verb(vpMeaning != null)} vào VietPhrase',
          onPressed: () {
            editableTextState.hideToolbar();
            showSharedEntryEditDialog(
              context,
              ref,
              word: word,
              kind: SharedDictionaryKind.vietPhrase,
            );
          },
        ),
        IconContextMenuItem(
          icon: Icons.local_library_outlined,
          iconColor: meaningLabelColor('Lạc Việt', scheme),
          label: '${verb(lacVietMeaning != null)} vào Lạc Việt',
          onPressed: () {
            editableTextState.hideToolbar();
            showSharedEntryEditDialog(
              context,
              ref,
              word: word,
              kind: SharedDictionaryKind.lacViet,
            );
          },
        ),
      ]);
    } else {
      custom.add(
        IconContextMenuItem(
          icon: Icons.person_add_alt_1_outlined,
          iconColor: meaningLabelColor('UserDict', scheme),
          label: '${verb(userMeaning != null)} vào UserDict',
          onPressed: () {
            editableTextState.hideToolbar();
            showEntryEditDialog(
              context,
              ref,
              word: word,
              toNames: false,
              title: '${verb(userMeaning != null)} vào UserDict',
              initialMeaning: userMeaning ?? vpMeaning,
            );
          },
        ),
      );
    }
    custom.add(
      IconContextMenuItem(
        icon: Icons.badge_outlined,
        iconColor: meaningLabelColor('Names', scheme),
        label: '${verb(namesMeaning != null)} vào Names',
        onPressed: () {
          editableTextState.hideToolbar();
          showEntryEditDialog(
            context,
            ref,
            word: word,
            toNames: true,
            title: '${verb(namesMeaning != null)} vào Names',
            initialMeaning: namesMeaning ?? defaultNamesMeaning,
          );
        },
      ),
    );
    custom.add(
      IconContextMenuItem(
        icon: Icons.travel_explore,
        iconColor: meaningLabelColor('Google Dịch', scheme),
        label: 'Tra online',
        onPressed: () {
          editableTextState.hideToolbar();
          // Tra key CJK của vùng chọn, không phải nghĩa tiếng Việt hiển thị.
          ref.read(lookupControllerProvider.notifier).lookup(word);
          showOnlineLookupDialog(context, ref, word: word);
        },
      ),
    );

    // Tô đen → chỉ hiện các mục Thêm/Sửa + Tra online (+ mục admin nếu
    // đăng nhập).
    return IconContextMenu(
      anchors: editableTextState.contextMenuAnchors,
      items: custom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sem = AppSemanticColors.of(context);
    final selection = ref.watch(tokenSelectionProvider);
    final paneStyle = ref.watch(
      settingsProvider.select((s) => s.paneTextStyleFor(widget.paneId)),
    );
    final rawKatakanaColor = ref.watch(
      settingsProvider.select((s) => s.katakanaColor),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color katakanaColor = Color(rawKatakanaColor);
    if (isDark) {
      if (rawKatakanaColor == const Color(0xFF202124).toARGB32() ||
          rawKatakanaColor == Colors.black.toARGB32()) {
        katakanaColor = Colors.white;
      } else if (rawKatakanaColor == const Color(0xFF2E7D32).toARGB32()) {
        katakanaColor = const Color(
          0xFF66BB6A,
        ); // Xanh lục tươi sáng tương phản cao
      } else if (katakanaColor.computeLuminance() < 0.40) {
        katakanaColor = Color.lerp(katakanaColor, Colors.white, 0.65)!;
      }
    }
    final keepQuotes = ref.watch(
      settingsProvider.select((s) => s.keepSpecialQuotes),
    );
    final multiMeaningMode = ref.watch(
      settingsProvider.select((s) => s.multiMeaningDisplayMode),
    );
    final paras = TokenTextView.paragraphs(widget.tokens);
    // Đánh dấu cụm từ điển phụ (chỉ ô VietPhrase): sát khoảng cách / in nghiêng.
    final secondaryDisplay = widget.paneId == PaneId.vietPhrase
        ? ref.watch(settingsProvider.select((s) => s.secondaryPhraseDisplay))
        : SecondaryPhraseDisplay.off;
    final secondaryPhrases = secondaryDisplay == SecondaryPhraseDisplay.off
        ? const <SecondaryPhrase>[]
        : ref.watch(secondaryPhrasesProvider);

    return Listener(
      // Ghi vị trí chuột phải TRƯỚC khi framework mở toolbar — _contextMenu
      // dùng vị trí này để biết từ nào bị nhấn (selection không tin được).
      onPointerDown: (event) {
        if ((event.buttons & kSecondaryMouseButton) != 0) {
          _secondaryTapPosition = event.position;
          _ignoreCollapsedSelection = true;
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: paras.length,
        itemBuilder: (context, index) {
          final pieces = TokenTextView._pieces(
            paras[index],
            widget.textOf,
            keepSpecialQuotes: keepQuotes,
          );
          final spans = <InlineSpan>[];
          // Range hiển thị (offset trong text của đoạn) → token, để map caret.
          final ranges = <(int, int, Token)>[];
          var offset = 0;
          for (var i = 0; i < pieces.length; i++) {
            final token = pieces[i].token;
            final text = pieces[i].text;
            final phrase = _secondaryPhraseAt(secondaryPhrases, token);
            var style = _styleFor(token, scheme, sem, selection, katakanaColor);
            if (secondaryDisplay == SecondaryPhraseDisplay.italic &&
                phrase != null) {
              style = style.copyWith(fontStyle: FontStyle.italic);
            }
            final isTokenSelected =
                selection != null &&
                token.kind != TokenKind.passthrough &&
                token.sourceStart < selection.end &&
                selection.start < token.sourceStart + token.source.length;

            final tokenSpan = _buildTokenSpan(
              token: token,
              text: text,
              baseStyle: style,
              scheme: scheme,
              sem: sem,
              isSelected: isTokenSelected,
              multiMeaningMode: multiMeaningMode,
            );
            spans.add(tokenSpan);
            if (token.kind != TokenKind.passthrough) {
              ranges.add((offset, offset + text.length, token));
            }
            offset += text.length;
            if (i + 1 < pieces.length &&
                TokenTextView._needSpaceBetween(text, pieces[i + 1].text)) {
              // Sát khoảng cách: bỏ space giữa hai mảnh cùng một cụm phụ.
              final tightSame =
                  secondaryDisplay == SecondaryPhraseDisplay.tight &&
                  phrase != null &&
                  identical(
                    phrase,
                    _secondaryPhraseAt(secondaryPhrases, pieces[i + 1].token),
                  );
              if (!tightSame) {
                spans.add(const TextSpan(text: ' '));
                offset += 1;
              }
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SelectableText.rich(
              TextSpan(style: paneStyle, children: spans),
              onSelectionChanged: (textSelection, cause) {
                // Bôi đen (không collapsed) → không đổi cụm đang chọn.
                if (!textSelection.isValid || !textSelection.isCollapsed) {
                  return;
                }
                // Chuột phải chỉ chèn nghĩa/mở menu, không active cụm.
                if (_ignoreCollapsedSelection) return;
                final caret = textSelection.baseOffset;
                for (final (start, end, token) in ranges) {
                  if (caret >= start && caret < end) {
                    ref
                        .read(tokenSelectionProvider.notifier)
                        .selectToken(token);
                    return;
                  }
                }
              },
              contextMenuBuilder: (context, editableTextState) =>
                  _contextMenu(editableTextState, ranges, paras[index]),
            ),
          );
        },
      ),
    );
  }
}
