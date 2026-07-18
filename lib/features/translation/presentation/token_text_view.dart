import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../dictionary/domain/dict_type.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../application/token_selection.dart';
import '../domain/token.dart';

/// Danh sách token dạng SelectableText: nháy chuột vào chữ (kiểu caret trong
/// edittext) → chọn cụm tại vị trí đó, tô nổi đỏ đồng bộ mọi pane + tra Nghĩa.
/// Chuột phải → toolbar có "Sửa nghĩa"/"Thêm vào Names".
/// [textOf] quyết định văn bản hiển thị (display / displayAll).
class TokenTextView extends ConsumerWidget {
  const TokenTextView({
    super.key,
    required this.tokens,
    required this.textOf,
    required this.paneId,
  });

  final List<Token> tokens;
  final String Function(Token) textOf;
  final PaneId paneId;

  /// Ghép text thuần từ [tokens] theo cùng quy tắc render (dùng cho nút copy).
  static String plainText(List<Token> tokens, String Function(Token) textOf) {
    return paragraphs(tokens)
        .map((p) {
          final sb = StringBuffer();
          for (var i = 0; i < p.length; i++) {
            final t = p[i];
            var text = textOf(t);
            if (_shouldCapitalize(p, i, textOf)) {
              text = _capitalize(text);
            }
            sb.write(text);
            if (t.kind != TokenKind.passthrough) {
              final next = (i + 1 < p.length) ? p[i + 1] : null;
              final nextText = next != null ? textOf(next) : '';
              if (!_isPunctuation(nextText)) {
                sb.write(' ');
              }
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

  TextStyle _styleFor(
    Token token,
    ColorScheme scheme,
    AppSemanticColors sem,
    TokenSelection? selection,
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
        return TextStyle(color: scheme.error);
      case TokenKind.passthrough:
        return TextStyle(color: scheme.onSurfaceVariant);
    }
  }

  Widget _contextMenu(
    BuildContext context,
    WidgetRef ref,
    EditableTextState editableTextState,
  ) {
    final selection = ref.read(tokenSelectionProvider);
    final items = [...editableTextState.contextMenuButtonItems];
    if (selection != null) {
      final dictionaryItems = <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          label: 'Sửa nghĩa "${selection.word}" (UserDict)',
          onPressed: () {
            editableTextState.hideToolbar();
            showEntryEditDialog(
              context,
              ref,
              word: selection.word,
              toNames: false,
            );
          },
        ),
        ContextMenuButtonItem(
          label: 'Thêm "${selection.word}" vào Names',
          onPressed: () {
            editableTextState.hideToolbar();
            showEntryEditDialog(
              context,
              ref,
              word: selection.word,
              toNames: true,
            );
          },
        ),
      ];
      if (ref.read(dictionarySyncProvider).isAdmin) {
        dictionaryItems.addAll([
          ContextMenuButtonItem(
            label: 'Cập nhật "${selection.word}" vào VietPhrase chung',
            onPressed: () {
              editableTextState.hideToolbar();
              showSharedEntryEditDialog(
                context,
                ref,
                word: selection.word,
                kind: SharedDictionaryKind.vietPhrase,
              );
            },
          ),
          ContextMenuButtonItem(
            label: 'Cập nhật "${selection.word}" vào Lạc Việt chung',
            onPressed: () {
              editableTextState.hideToolbar();
              showSharedEntryEditDialog(
                context,
                ref,
                word: selection.word,
                kind: SharedDictionaryKind.lacViet,
              );
            },
          ),
        ]);
      }
      items.insertAll(0, dictionaryItems);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sem = AppSemanticColors.of(context);
    final selection = ref.watch(tokenSelectionProvider);
    final paneStyle = ref.watch(
      settingsProvider.select((s) => s.paneTextStyleFor(paneId)),
    );
    final paras = paragraphs(tokens);

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: paras.length,
      itemBuilder: (context, index) {
        final paragraph = paras[index];
        final spans = <InlineSpan>[];
        // Range hiển thị (offset trong text của đoạn) → token, để map caret.
        final ranges = <(int, int, Token)>[];
        var offset = 0;
        for (var i = 0; i < paragraph.length; i++) {
          final token = paragraph[i];
          var text = textOf(token);
          if (_shouldCapitalize(paragraph, i, textOf)) {
            text = _capitalize(text);
          }
          spans.add(
            TextSpan(
              text: text,
              style: _styleFor(token, scheme, sem, selection),
            ),
          );
          if (token.kind != TokenKind.passthrough) {
            ranges.add((offset, offset + text.length, token));
          }
          offset += text.length;
          if (token.kind != TokenKind.passthrough) {
            final next = (i + 1 < paragraph.length) ? paragraph[i + 1] : null;
            final nextText = next != null ? textOf(next) : '';
            if (!_isPunctuation(nextText)) {
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
              if (!textSelection.isValid || !textSelection.isCollapsed) {
                return;
              }
              final caret = textSelection.baseOffset;
              for (final (start, end, token) in ranges) {
                if (caret >= start && caret < end) {
                  ref.read(tokenSelectionProvider.notifier).selectToken(token);
                  return;
                }
              }
            },
            contextMenuBuilder: (context, editableTextState) =>
                _contextMenu(context, ref, editableTextState),
          ),
        );
      },
    );
  }

  static bool _isPunctuation(String text) {
    if (text.isEmpty) return false;
    final char = text.trim();
    if (char.isEmpty) return false;
    final first = char[0];
    return const {',', '.', '!', '?', ':', ';', ')', '}', ']'}.contains(first);
  }

  /// Ký tự kết câu (ASCII + toàn-hình CJK) → chữ Việt kế tiếp viết hoa.
  static const _sentenceEnders = {'.', '!', '?', '…', '。', '．', '！', '？', '⋯'};

  static bool _shouldCapitalize(
    List<Token> paragraph,
    int index,
    String Function(Token) textOf,
  ) {
    if (index == 0) return true;
    for (var j = index - 1; j >= 0; j--) {
      final prevText = textOf(paragraph[j]).trim();
      if (prevText.isEmpty) continue;
      final lastChar = prevText[prevText.length - 1];
      if (_sentenceEnders.contains(lastChar)) {
        return true;
      }
      break;
    }
    return false;
  }

  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (RegExp(r'[a-zA-Zà-ỹÀ-Ỹ]').hasMatch(char)) {
        return text.substring(0, i) +
            char.toUpperCase() +
            text.substring(i + 1);
      }
      if (RegExp(r'[0-9]').hasMatch(char)) break;
    }
    return text;
  }
}
