import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../dictionary/domain/dict_type.dart';
import '../application/lookup_controller.dart';
import '../domain/token.dart';

/// Danh sách token dạng RichText: mỗi đoạn (ngăn bởi newline) là 1 RichText,
/// token click trái → tra LacViet, chuột phải → menu sửa từ điển.
/// [textOf] quyết định văn bản hiển thị (display / displayAll).
class TokenTextView extends ConsumerStatefulWidget {
  const TokenTextView({super.key, required this.tokens, required this.textOf});

  final List<Token> tokens;
  final String Function(Token) textOf;

  /// Ghép text thuần từ [tokens] theo cùng quy tắc render (dùng cho nút copy).
  static String plainText(List<Token> tokens, String Function(Token) textOf) {
    return paragraphs(tokens)
        .map((p) => p
            .map((t) =>
                t.kind == TokenKind.passthrough ? textOf(t) : '${textOf(t)} ')
            .join()
            .trimRight())
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
            paragraphs.last.add(Token(
              source: text,
              sourceStart: token.sourceStart,
              kind: TokenKind.passthrough,
            ));
          }
        }
      } else {
        paragraphs.last.add(token);
      }
    }
    paragraphs.removeWhere((p) => p.isEmpty);
    return paragraphs;
  }

  @override
  ConsumerState<TokenTextView> createState() => _TokenTextViewState();
}

class _TokenTextViewState extends ConsumerState<TokenTextView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextStyle _styleFor(Token token, ColorScheme scheme) {
    switch (token.kind) {
      case TokenKind.matched:
        switch (token.dictType) {
          case DictType.userDict:
            return TextStyle(
                color: scheme.tertiary, fontWeight: FontWeight.w600);
          case DictType.names:
            return const TextStyle(
                color: Colors.teal, fontWeight: FontWeight.w600);
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

  Future<void> _showTokenMenu(Offset globalPosition, Token token) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final toNames = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
          globalPosition & Size.zero, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: false,
          child: Text('Sửa nghĩa "${token.source}" (UserDict)'),
        ),
        PopupMenuItem(
          value: true,
          child: Text('Thêm "${token.source}" vào Names'),
        ),
      ],
    );
    if (toNames == null || !mounted) return;
    await showEntryEditDialog(context, ref,
        word: token.source, toNames: toNames);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    _disposeRecognizers();

    final paragraphs = TokenTextView.paragraphs(widget.tokens);

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: paragraphs.length,
      itemBuilder: (context, index) {
        final paragraph = paragraphs[index];
        final spans = <InlineSpan>[];
        for (final token in paragraph) {
          final tappable = token.kind == TokenKind.matched ||
              token.kind == TokenKind.hanViet ||
              token.kind == TokenKind.unmatched;
          TapGestureRecognizer? recognizer;
          if (tappable) {
            recognizer = TapGestureRecognizer()
              ..onTap = () {
                ref
                    .read(lookupControllerProvider.notifier)
                    .lookup(token.source);
              }
              ..onSecondaryTapDown =
                  (details) => _showTokenMenu(details.globalPosition, token);
            _recognizers.add(recognizer);
          }
          spans.add(TextSpan(
            text: widget.textOf(token),
            style: _styleFor(token, scheme),
            recognizer: recognizer,
          ));
          if (tappable) spans.add(const TextSpan(text: ' '));
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 15, height: 1.5),
              children: spans,
            ),
          ),
        );
      },
    );
  }
}
