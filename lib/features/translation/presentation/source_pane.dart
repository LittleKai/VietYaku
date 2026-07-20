import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/icon_context_menu.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../application/lookup_controller.dart';
import '../application/token_selection.dart';
import '../application/translation_controller.dart';

import '../domain/token.dart';

/// Nội dung ô Nguồn đang gõ (nút Dịch trên menu bar đọc giá trị này).
final sourceDraftProvider = StateProvider<String>((ref) => '');

/// TextEditingController tô nổi đỏ cụm đang chọn (click) và cụm đang rê chuột
/// (hover) + tô đậm tất cả các từ có trong từ điển.
class _HighlightTextEditingController extends TextEditingController {
  TextRange? _highlight;
  TextRange? _hover;
  List<Token> _tokens = const [];

  void setHighlight(TextRange? range) {
    if (range == _highlight) return;
    _highlight = range;
    notifyListeners();
  }

  void setHover(TextRange? range) {
    if (range == _hover) return;
    _hover = range;
    notifyListeners();
  }

  void setTokens(List<Token> tokens) {
    _tokens = tokens;
    notifyListeners();
  }

  bool _overlaps(TextRange? r, int start, int end) {
    if (r == null) return false;
    final s = r.start.clamp(0, text.length);
    final e = r.end.clamp(0, text.length);
    return s < e && start < e && s < end;
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

    final hasRanges = !withComposing && (_highlight != null || _hover != null);

    if (_tokens.isEmpty && !hasRanges) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final hl = AppSemanticColors.of(context).highlight;
    final spans = <TextSpan>[];
    final totalTokenLen = _tokens.fold(0, (sum, t) => sum + t.source.length);

    if (_tokens.isNotEmpty && totalTokenLen == text.length) {
      for (final token in _tokens) {
        final tStart = token.sourceStart;
        final tEnd = tStart + token.source.length;

        final isRed =
            _overlaps(_highlight, tStart, tEnd) ||
            _overlaps(_hover, tStart, tEnd);

        var tokenStyle = style ?? const TextStyle();
        if (isRed) {
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
      // Fallback khi gõ dở hoặc lệch tokens: chỉ tô range highlight.
      final raw = _highlight;
      final hs = raw == null ? 0 : raw.start.clamp(0, text.length);
      final he = raw == null ? 0 : raw.end.clamp(0, text.length);
      if (raw != null && !withComposing && hs < he) {
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

class SourcePopupPlacement {
  const SourcePopupPlacement({this.top, this.bottom, required this.maxHeight});

  final double? top;
  final double? bottom;
  final double maxHeight;

  bool get isBelow => top != null;
}

/// Chọn phía có nhiều chỗ trống hơn để popup không che dòng đang active.
SourcePopupPlacement calculateSourcePopupPlacement({
  required double panelHeight,
  required double lineTop,
  required double lineBottom,
}) {
  const gap = 8.0;
  const preferredHeight = 260.0;
  final safeTop = lineTop.clamp(0.0, panelHeight);
  final safeBottom = lineBottom.clamp(safeTop, panelHeight);
  final spaceAbove = math.max(0.0, safeTop - gap);
  final spaceBelow = math.max(0.0, panelHeight - safeBottom - gap);
  if (spaceBelow >= spaceAbove) {
    return SourcePopupPlacement(
      top: safeBottom + gap,
      maxHeight: math.min(preferredHeight, math.max(1.0, spaceBelow)),
    );
  }
  return SourcePopupPlacement(
    bottom: panelHeight - safeTop + gap,
    maxHeight: math.min(preferredHeight, math.max(1.0, spaceAbove)),
  );
}

class SourcePane extends ConsumerStatefulWidget {
  const SourcePane({super.key});

  @override
  ConsumerState<SourcePane> createState() => _SourcePaneState();
}

class _SourcePaneState extends ConsumerState<SourcePane> {
  final _controller = _HighlightTextEditingController();
  final _scrollController = ScrollController();
  final _fieldKey = GlobalKey();
  int _lastCaret = -1;

  static const _padding = 12.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCaretMaybeChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (mounted && ref.read(tokenSelectionProvider) != null) setState(() {});
  }

  SourcePopupPlacement? _popupPlacement(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle style,
    TokenSelection? selection,
  ) {
    if (selection == null || _controller.text.isEmpty) return null;
    final position = TextPosition(
      offset: selection.start.clamp(0, _controller.text.length),
    );
    final painter = TextPainter(
      text: TextSpan(text: _controller.text, style: style),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: math.max(1.0, constraints.maxWidth - 2 * _padding));
    final caretPrototype = Rect.fromLTWH(0, 0, 1, style.fontSize ?? 14);
    final caretOffset = painter.getOffsetForCaret(position, caretPrototype);
    final lineHeight = painter.getFullHeightForCaret(position, caretPrototype);
    painter.dispose();
    final scrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final lineTop = _padding + caretOffset.dy - scrollOffset;
    return calculateSourcePopupPlacement(
      panelHeight: constraints.maxHeight,
      lineTop: lineTop,
      lineBottom: lineTop + lineHeight,
    );
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

  /// Tìm RenderEditable thật của TextField (đo vị trí chính xác pixel-cho-
  /// pixel, tránh lệch vài ký tự do TextPainter tự dựng khác metrics thật —
  /// xem .claude/IMPORTANT_FIXED_BUGS.md 2026-07-19).
  RenderEditable? _findRenderEditable() {
    final root = _fieldKey.currentContext?.findRenderObject();
    if (root == null) return null;
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// Rê chuột → tô đỏ cụm dưới con trỏ (không tra, chỉ preview).
  void _onHover(Offset globalPosition) {
    if (_controller.text !=
        ref.read(translationControllerProvider).sourceText) {
      _controller.setHover(null);
      return;
    }
    final renderEditable = _findRenderEditable();
    if (renderEditable == null) {
      _controller.setHover(null);
      return;
    }
    final offset = renderEditable.getPositionForPoint(globalPosition).offset;

    final tokens = ref.read(translationControllerProvider).tokens;
    for (final t in tokens) {
      if (t.kind == TokenKind.passthrough) continue;
      if (offset >= t.sourceStart && offset < t.sourceStart + t.source.length) {
        _controller.setHover(
          TextRange(start: t.sourceStart, end: t.sourceStart + t.source.length),
        );
        return;
      }
    }
    _controller.setHover(null);
  }

  Widget _buildEditor(BuildContext context, TextStyle style) {
    return TextField(
      key: _fieldKey,
      controller: _controller,
      scrollController: _scrollController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: style,
      onChanged: (value) =>
          ref.read(sourceDraftProvider.notifier).state = value,
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(_padding),
        hintText: 'Dán văn bản Nhật/Trung vào đây…',
      ),
      contextMenuBuilder: (context, editableTextState) {
        final value = editableTextState.textEditingValue;
        final selection = value.selection.textInside(value.text).trim();
        if (selection.isEmpty) return const SizedBox.shrink();

        final dicts = ref.read(dictionariesProvider).valueOrNull;
        final userMeaning = dicts?.userDict.entries[selection];
        final vpMeaning = dicts?.vietPhrase.entries[selection];
        final lacVietMeaning = dicts?.lacViet.entries[selection];
        final namesMeaning = dicts?.names.entries[selection];
        final isAdmin = ref.read(dictionarySyncProvider).isAdmin;
        String verb(bool exists) => exists ? 'Sửa' : 'Thêm';
        void hide() => editableTextState.hideToolbar();

        final items = <IconContextMenuItem>[];
        if (isAdmin) {
          items.addAll([
            IconContextMenuItem(
              icon: Icons.menu_book_outlined,
              label: '${verb(vpMeaning != null)} vào VietPhrase',
              onPressed: () {
                hide();
                showSharedEntryEditDialog(
                  this.context,
                  ref,
                  word: selection,
                  kind: SharedDictionaryKind.vietPhrase,
                );
              },
            ),
            IconContextMenuItem(
              icon: Icons.local_library_outlined,
              label: '${verb(lacVietMeaning != null)} vào Lạc Việt',
              onPressed: () {
                hide();
                showSharedEntryEditDialog(
                  this.context,
                  ref,
                  word: selection,
                  kind: SharedDictionaryKind.lacViet,
                );
              },
            ),
          ]);
        } else {
          items.add(
            IconContextMenuItem(
              icon: Icons.person_add_alt_1_outlined,
              label: '${verb(userMeaning != null)} vào UserDict',
              onPressed: () {
                hide();
                showEntryEditDialog(
                  this.context,
                  ref,
                  word: selection,
                  toNames: false,
                  title: '${verb(userMeaning != null)} vào UserDict',
                  initialMeaning: userMeaning ?? vpMeaning,
                );
              },
            ),
          );
        }
        items.addAll([
          IconContextMenuItem(
            icon: Icons.badge_outlined,
            label: '${verb(namesMeaning != null)} vào Names',
            onPressed: () {
              hide();
              showEntryEditDialog(
                this.context,
                ref,
                word: selection,
                toNames: true,
                title: '${verb(namesMeaning != null)} vào Names',
                initialMeaning: namesMeaning,
              );
            },
          ),
          IconContextMenuItem(
            icon: Icons.travel_explore,
            label: 'Tra thêm nghĩa online',
            onPressed: () async {
              hide();
              ref.read(lookupControllerProvider.notifier).lookup(selection);
              final ok = await ref
                  .read(lookupControllerProvider.notifier)
                  .fetchOnlineMeaning();
              if (!mounted || ok) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Không lấy được nghĩa online.')),
              );
            },
          ),
        ]);
        return IconContextMenu(
          anchors: editableTextState.contextMenuAnchors,
          items: items,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(
      settingsProvider.select((s) => s.paneTextStyleFor(PaneId.source)),
    );
    final selection = ref.watch(tokenSelectionProvider);
    final result = ref.watch(lookupControllerProvider);
    final popupTypes = ref.watch(
      settingsProvider.select((s) => s.popupDictionaryTypes),
    );
    final popupSections =
        selection?.origin == TokenSelectionOrigin.source && result != null
        ? result.sections
              .where((section) => popupTypes.contains(section.dictionaryType))
              .toList(growable: false)
        : const <LookupSection>[];

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final placement = popupSections.isEmpty
                      ? null
                      : _popupPlacement(context, constraints, style, selection);
                  final popupWidth = math.max(
                    1.0,
                    math.min(380.0, constraints.maxWidth - 20),
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: MouseRegion(
                          onHover: (event) => _onHover(event.position),
                          onExit: (_) => _controller.setHover(null),
                          child: _buildEditor(context, style),
                        ),
                      ),
                      if (placement != null)
                        Positioned(
                          top: placement.top,
                          bottom: placement.bottom,
                          right: 10,
                          child: _SourceLookupPopup(
                            sections: popupSections,
                            maxWidth: popupWidth,
                            maxHeight: placement.maxHeight,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceLookupPopup extends StatelessWidget {
  const _SourceLookupPopup({
    required this.sections,
    required this.maxWidth,
    required this.maxHeight,
  });

  final List<LookupSection> sections;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < sections.length; index++) ...[
                if (index > 0)
                  Divider(height: 18, color: scheme.outlineVariant),
                Text(
                  '${sections[index].word} <<${sections[index].label}>>',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(sections[index].body),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
