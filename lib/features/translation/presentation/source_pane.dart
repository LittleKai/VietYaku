import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../settings/settings_provider.dart';
import '../application/token_selection.dart';
import '../application/translation_controller.dart';

import '../domain/token.dart';

/// Nội dung ô Nguồn đang gõ (nút Dịch trên menu bar đọc giá trị này).
final sourceDraftProvider = StateProvider<String>((ref) => '');

/// TextEditingController tô nổi đỏ cụm đang chọn + tô đậm tất cả các từ có trong từ điển.
class _HighlightTextEditingController extends TextEditingController {
  TextRange? _highlight;
  List<Token> _tokens = const [];

  void setHighlight(TextRange? range) {
    if (range == _highlight) return;
    _highlight = range;
    notifyListeners();
  }

  void setTokens(List<Token> tokens) {
    _tokens = tokens;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // Clamp range chọn về [0, text.length]: vẫn tô đỏ khi tokens/selection lệch
    // nhẹ (vd offset chọn hơi vượt biên) thay vì mất hẳn màu.
    final raw = _highlight;
    final hs = raw == null ? 0 : raw.start.clamp(0, text.length);
    final he = raw == null ? 0 : raw.end.clamp(0, text.length);
    final hasHighlight = raw != null && !withComposing && hs < he;

    // Nếu không có tokens và không có highlight, dùng mặc định
    if (_tokens.isEmpty && !hasHighlight) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final hl = AppSemanticColors.of(context).highlight;
    final spans = <TextSpan>[];
    int totalTokenLen = _tokens.fold(0, (sum, t) => sum + t.source.length);

    if (_tokens.isNotEmpty && totalTokenLen == text.length) {
      for (final token in _tokens) {
        final tStart = token.sourceStart;
        final tEnd = tStart + token.source.length;

        bool isHighlighted = hasHighlight && tStart < he && hs < tEnd;

        TextStyle tokenStyle = style ?? const TextStyle();
        if (isHighlighted) {
          tokenStyle = tokenStyle.copyWith(
            color: hl,
            fontWeight: FontWeight.bold,
          );
        } else if (token.kind == TokenKind.matched) {
          tokenStyle = tokenStyle.copyWith(fontWeight: FontWeight.bold);
        }

        spans.add(TextSpan(text: token.source, style: tokenStyle));
      }
    } else {
      // Fallback khi gõ dở hoặc lệch tokens
      if (hasHighlight) {
        final highlightStyle = (style ?? const TextStyle()).copyWith(
          color: hl,
          fontWeight: FontWeight.bold,
        );
        if (hs > 0) {
          spans.add(TextSpan(text: text.substring(0, hs), style: style));
        }
        spans.add(
          TextSpan(text: text.substring(hs, he), style: highlightStyle),
        );
        if (he < text.length) {
          spans.add(TextSpan(text: text.substring(he), style: style));
        }
      } else {
        spans.add(TextSpan(text: text, style: style));
      }
    }

    return TextSpan(style: style, children: spans);
  }
}

class SourcePane extends ConsumerStatefulWidget {
  const SourcePane({super.key});

  @override
  ConsumerState<SourcePane> createState() => _SourcePaneState();
}

class _SourcePaneState extends ConsumerState<SourcePane> {
  final _controller = _HighlightTextEditingController();
  int _lastCaret = -1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCaretMaybeChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nháy chuột trong văn bản đã dịch → chọn cụm chứa caret (kiểu QT).
  void _onCaretMaybeChanged() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    if (_controller.text !=
        ref.read(translationControllerProvider).sourceText) {
      return; // text đang gõ dở, chưa dịch — không tra
    }
    if (selection.baseOffset == _lastCaret) return;
    _lastCaret = selection.baseOffset;
    ref
        .read(tokenSelectionProvider.notifier)
        .selectAtSourceOffset(selection.baseOffset);
  }

  Widget _buildEditor(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: ref.watch(
        settingsProvider.select((s) => s.paneTextStyleFor(PaneId.source)),
      ),
      onChanged: (value) =>
          ref.read(sourceDraftProvider.notifier).state = value,
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
        hintText: 'Dán văn bản Nhật/Trung vào đây…',
      ),
      contextMenuBuilder: (context, editableTextState) {
        final value = editableTextState.textEditingValue;
        final selection = value.selection.textInside(value.text).trim();
        final items = [...editableTextState.contextMenuButtonItems];
        if (selection.isNotEmpty) {
          items.insert(
            0,
            ContextMenuButtonItem(
              label: 'Thêm vào Names',
              onPressed: () {
                editableTextState.hideToolbar();
                showEntryEditDialog(
                  context,
                  ref,
                  word: selection,
                  toNames: true,
                );
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tô nổi cụm đang chọn (đồng bộ với các pane khác).
    ref.listen(tokenSelectionProvider, (previous, next) {
      _controller.setHighlight(
        next == null ? null : TextRange(start: next.start, end: next.end),
      );
    });

    // Đồng bộ text khi dịch được kích hoạt từ ngoài (Dán & Dịch trên menu bar).
    ref.listen(translationControllerProvider.select((s) => s.sourceText), (
      previous,
      next,
    ) {
      if (_controller.text != next && next.isNotEmpty) {
        _controller.text = next;
        ref.read(sourceDraftProvider.notifier).state = next;
      }
    });

    // Lắng nghe danh sách tokens khi dịch xong để tô đậm các từ có trong từ điển
    ref.listen(translationControllerProvider.select((s) => s.tokens), (
      previous,
      next,
    ) {
      _controller.setTokens(next);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildEditor(context),
            ),
          ),
        ),
      ],
    );
  }
}
