import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/domain/dict_type.dart';
import '../application/lookup_controller.dart';
import '../application/translation_controller.dart';
import '../domain/token.dart';

/// Kết quả dịch: mỗi đoạn (ngăn bởi newline) là 1 RichText,
/// mỗi token có TapGestureRecognizer để tra LacViet.
class ResultPane extends ConsumerStatefulWidget {
  const ResultPane({super.key});

  @override
  ConsumerState<ResultPane> createState() => _ResultPaneState();
}

class _ResultPaneState extends ConsumerState<ResultPane> {
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

  /// Tách token thành các đoạn theo newline trong passthrough.
  static List<List<Token>> _paragraphs(List<Token> tokens) {
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
        return TextStyle(
            color: scheme.primary, fontStyle: FontStyle.italic);
      case TokenKind.unmatched:
        return TextStyle(color: scheme.error);
      case TokenKind.passthrough:
        return TextStyle(color: scheme.onSurfaceVariant);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translationControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    _disposeRecognizers();

    if (!state.hasResult) {
      return const Center(child: Text('Kết quả dịch sẽ hiện ở đây'));
    }

    final paragraphs = _paragraphs(state.tokens);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Text(
                '${state.tokens.length} token · ${state.elapsedMs}ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy kết quả dịch',
                onPressed: () {
                  final text = paragraphs
                      .map((p) => p
                          .map((t) => t.kind == TokenKind.passthrough
                              ? t.display
                              : '${t.display} ')
                          .join()
                          .trimRight())
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã copy kết quả'),
                    duration: Duration(seconds: 1),
                  ));
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
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
                    ..onTap = () => ref
                        .read(lookupControllerProvider.notifier)
                        .lookup(token.source);
                  _recognizers.add(recognizer);
                }
                spans.add(TextSpan(
                  text: token.display,
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
          ),
        ),
      ],
    );
  }
}
