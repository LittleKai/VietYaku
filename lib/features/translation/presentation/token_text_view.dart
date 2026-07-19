import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cjk.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/domain/dict_type.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../application/token_selection.dart';
import '../application/viet_draft.dart';
import '../domain/token.dart';

/// Một token đã tính text hiển thị (đã chuẩn hoá + viết hoa).
typedef _Piece = ({Token token, String text});

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
          final pieces = _pieces(p, textOf, keepSpecialQuotes: keepSpecialQuotes);
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
    for (var i = 0; i < text.length; i++) {
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
}

class _TokenTextViewState extends ConsumerState<TokenTextView> {
  /// Vị trí global của lần nhấn chuột phải gần nhất. Trên Windows,
  /// SelectableText đã có focus thì chuột phải KHÔNG dời caret/selection
  /// (text_selection.dart onSecondaryTap) → không dùng selection để biết
  /// từ nào bị nhấn; map điểm nhấn qua renderEditable.getPositionForPoint.
  Offset? _secondaryTapPosition;

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
  /// "[a/b/c]" → lấy đúng nghĩa dưới con trỏ; một nghĩa → cả text.
  static String _meaningAt(String text, int rel) {
    var start = 0;
    var end = text.length;
    for (var i = 0; i < text.length; i++) {
      if (text[i] != '/') continue;
      if (i < rel) {
        start = i + 1;
      } else {
        end = i;
        break;
      }
    }
    return text
        .substring(start, end)
        .replaceAll('[', '')
        .replaceAll(']', '')
        .trim();
  }

  Widget _contextMenu(
    BuildContext context,
    EditableTextState editableTextState,
    List<(int, int, Token)> ranges,
  ) {
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
          ref.read(tokenSelectionProvider.notifier).selectToken(token);
          insertIntoVietDraft(ref.read(vietDraftControllerProvider), meaning);
        }
      });
      return const SizedBox.shrink();
    }

    // Tô đen → key từ điển là source CJK của các token nằm trong vùng chọn
    // (text hiển thị là nghĩa tiếng Việt, không phải key tra được).
    final key = [
      for (final (start, end, token) in ranges)
        if (start < sel.end && sel.start < end) token.source,
    ].join();
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
    String verb(bool exists) => exists ? 'Sửa' : 'Thêm';

    final custom = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '${verb(userMeaning != null || vpMeaning != null)} '
            '"$word" (VietPhrase)',
        onPressed: () {
          editableTextState.hideToolbar();
          showEntryEditDialog(
            context,
            ref,
            word: word,
            toNames: false,
            title: '${verb(userMeaning != null || vpMeaning != null)} '
                '(VietPhrase)',
            initialMeaning: userMeaning ?? vpMeaning,
          );
        },
      ),
      ContextMenuButtonItem(
        label: '${verb(lacVietMeaning != null)} "$word" (Lạc Việt)',
        onPressed: () {
          editableTextState.hideToolbar();
          showEntryEditDialog(
            context,
            ref,
            word: word,
            toNames: false,
            title: '${verb(lacVietMeaning != null)} (Lạc Việt)',
            initialMeaning: userMeaning ?? lacVietMeaning,
          );
        },
      ),
      ContextMenuButtonItem(
        label: '${verb(namesMeaning != null)} "$word" (Names)',
        onPressed: () {
          editableTextState.hideToolbar();
          showEntryEditDialog(
            context,
            ref,
            word: word,
            toNames: true,
            title: '${verb(namesMeaning != null)} (Names)',
            initialMeaning: namesMeaning,
          );
        },
      ),
    ];
    if (ref.read(dictionarySyncProvider).isAdmin) {
      custom.addAll([
        ContextMenuButtonItem(
          label: 'Cập nhật "$word" vào VietPhrase chung',
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
        ContextMenuButtonItem(
          label: 'Cập nhật "$word" vào Lạc Việt chung',
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
    }

    // Tô đen → chỉ hiện các mục Thêm/Sửa (+ mục admin nếu đăng nhập).
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: custom,
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
    final katakanaColor = Color(
      ref.watch(settingsProvider.select((s) => s.katakanaColor)),
    );
    final keepQuotes = ref.watch(
      settingsProvider.select((s) => s.keepSpecialQuotes),
    );
    final paras = TokenTextView.paragraphs(widget.tokens);

    return Listener(
      // Ghi vị trí chuột phải TRƯỚC khi framework mở toolbar — _contextMenu
      // dùng vị trí này để biết từ nào bị nhấn (selection không tin được).
      onPointerDown: (event) {
        if ((event.buttons & kSecondaryMouseButton) != 0) {
          _secondaryTapPosition = event.position;
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
            spans.add(
              TextSpan(
                text: text,
                style: _styleFor(token, scheme, sem, selection, katakanaColor),
              ),
            );
            if (token.kind != TokenKind.passthrough) {
              ranges.add((offset, offset + text.length, token));
            }
            offset += text.length;
            if (i + 1 < pieces.length &&
                TokenTextView._needSpaceBetween(text, pieces[i + 1].text)) {
              spans.add(const TextSpan(text: ' '));
              offset += 1;
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
                  _contextMenu(context, editableTextState, ranges),
            ),
          );
        },
      ),
    );
  }
}
