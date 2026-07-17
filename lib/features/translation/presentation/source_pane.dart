import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/tts_button.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../application/token_selection.dart';
import '../application/translation_controller.dart';

import '../domain/token.dart';

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
          context: context, style: style, withComposing: withComposing);
    }

    final h = _highlight;
    final hasHighlight = h != null &&
        !withComposing &&
        h.start >= 0 &&
        h.end <= text.length &&
        h.start < h.end;

    // Nếu không có tokens và không có highlight, dùng mặc định
    if (_tokens.isEmpty && !hasHighlight) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    final spans = <TextSpan>[];
    int totalTokenLen = _tokens.fold(0, (sum, t) => sum + t.source.length);

    if (_tokens.isNotEmpty && totalTokenLen == text.length) {
      for (final token in _tokens) {
        final tStart = token.sourceStart;
        final tEnd = tStart + token.source.length;

        bool isHighlighted = hasHighlight && (tStart >= h.start && tEnd <= h.end);

        TextStyle tokenStyle = style ?? const TextStyle();
        if (isHighlighted) {
          tokenStyle = tokenStyle.copyWith(
              color: Colors.red, fontWeight: FontWeight.bold);
        } else if (token.kind == TokenKind.matched) {
          tokenStyle = tokenStyle.copyWith(fontWeight: FontWeight.bold);
        }

        spans.add(TextSpan(text: token.source, style: tokenStyle));
      }
    } else {
      // Fallback khi gõ dở hoặc lệch tokens
      if (hasHighlight) {
        final highlightStyle = (style ?? const TextStyle())
            .copyWith(color: Colors.red, fontWeight: FontWeight.bold);
        if (h.start > 0) spans.add(TextSpan(text: text.substring(0, h.start), style: style));
        spans.add(TextSpan(text: text.substring(h.start, h.end), style: highlightStyle));
        if (h.end < text.length) spans.add(TextSpan(text: text.substring(h.end), style: style));
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

  // Clipboard watcher (Phase 5b): poll 1s, text CJK mới → tự dán + dịch.
  bool _watchingClipboard = false;
  Timer? _clipboardTimer;
  String? _lastClipboard;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCaretMaybeChanged);
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
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

  Future<void> _toggleClipboardWatch() async {
    if (_watchingClipboard) {
      _clipboardTimer?.cancel();
      _clipboardTimer = null;
      setState(() => _watchingClipboard = false);
      return;
    }
    // Mồi giá trị hiện tại để chỉ phản ứng với text MỚI.
    _lastClipboard =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    _clipboardTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollClipboard());
    setState(() => _watchingClipboard = true);
  }

  Future<void> _pollClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text == _lastClipboard) return;
    _lastClipboard = text;
    if (!_containsCjk(text) || !mounted) return;
    _controller.text = text;
    _translate();
  }

  static bool _containsCjk(String text) {
    for (var i = 0; i < text.length; i++) {
      if (isCjkCodePoint(codePointAt(text, i))) return true;
    }
    return false;
  }

  void _translate() {
    ref
        .read(translationControllerProvider.notifier)
        .translate(_controller.text);
  }

  Widget _buildEditor(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: ref.watch(settingsProvider.select((s) => s.paneTextStyle())),
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
                showEntryEditDialog(context, ref,
                    word: selection, toNames: true);
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
    final mode =
        ref.watch(translationControllerProvider.select((s) => s.mode));
    final dictsLoading = ref.watch(dictionariesProvider).isLoading;

    // Tô nổi cụm đang chọn (đồng bộ với các pane khác).
    ref.listen(tokenSelectionProvider, (previous, next) {
      _controller.setHighlight(next == null
          ? null
          : TextRange(start: next.start, end: next.end));
    });

    // Đồng bộ text khi dịch được kích hoạt từ ngoài (Dán & Dịch trên menu bar).
    ref.listen(translationControllerProvider.select((s) => s.sourceText),
        (previous, next) {
      if (_controller.text != next && next.isNotEmpty) {
        _controller.text = next;
      }
    });

    // Lắng nghe danh sách tokens khi dịch xong để tô đậm các từ có trong từ điển
    ref.listen(translationControllerProvider.select((s) => s.tokens), (previous, next) {
      _controller.setTokens(next);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Theo dõi clipboard
              IconButton(
                icon: Icon(_watchingClipboard
                    ? Icons.visibility
                    : Icons.visibility_off_outlined),
                isSelected: _watchingClipboard,
                tooltip: _watchingClipboard
                    ? 'Đang theo dõi clipboard (bấm để tắt)'
                    : 'Theo dõi clipboard: tự dịch khi copy text CJK',
                onPressed: _toggleClipboardWatch,
                visualDensity: VisualDensity.compact,
              ),
              // Đọc TTS
              TtsButton(
                textProvider: () => _controller.text,
                mode: mode,
                tooltip: 'Đọc cả đoạn',
              ),
              const SizedBox(width: 4),
              // Nút Dịch chính
              FilledButton.icon(
                icon: const Icon(Icons.translate, size: 16),
                label: const Text('Dịch', style: TextStyle(fontSize: 13)),
                onPressed: dictsLoading ? null : _translate,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
