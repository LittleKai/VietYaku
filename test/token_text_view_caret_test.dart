import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/token_selection.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/presentation/token_text_view.dart';

/// Cụm đầu có 2 tầng nghĩa, cụm sau 1 nghĩa.
const _tokens = [
  Token(
    source: '行',
    sourceStart: 0,
    kind: TokenKind.matched,
    rawValue: 'hành/(2)/đi/bước',
  ),
  Token(source: '。', sourceStart: 1, kind: TokenKind.passthrough),
  Token(
    source: '人',
    sourceStart: 2,
    kind: TokenKind.matched,
    rawValue: 'người',
  ),
];

String _singleMeaningTextOf(Token t) => t.displayWithPartOfSpeech;
String _multiMeaningTextOf(Token t) => t.displayAllWith();

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String Function(Token) textOf,
  required bool multiMeaning,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: TokenTextView(
            tokens: _tokens,
            textOf: textOf,
            paneId: PaneId.vietPhrase,
            multiMeaning: multiMeaning,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

String _renderedText(WidgetTester tester) => tester
    .widget<SelectableText>(find.byType(SelectableText).first)
    .textSpan!
    .toPlainText(includeSemanticsLabels: false);

/// Click vào [target] (offset trong text đang hiển thị) rồi trả cụm được chọn.
Future<TokenSelection?> _tapAtTextOffset(
  WidgetTester tester,
  ProviderContainer container,
  int target,
) async {
  final renderEditable = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  final caretRect = renderEditable.getLocalRectForCaret(
    TextPosition(offset: target),
  );
  await tester.tapAt(
    renderEditable.localToGlobal(caretRect.center + const Offset(2, 0)),
  );
  await tester.pumpAndSettle();
  return container.read(tokenSelectionProvider);
}

void main() {
  testWidgets('tab một nghĩa chỉ hiện nghĩa đầu, không dựng lại từ rawValue', (
    tester,
  ) async {
    await _pump(
      tester,
      textOf: _singleMeaningTextOf,
      multiMeaning: false,
    );
    final rendered = _renderedText(tester);
    expect(rendered, contains('Hành'));
    expect(rendered, isNot(contains('đi')));
    expect(rendered, isNot(contains('bước')));
  });

  testWidgets('tab đa nghĩa vẫn hiện đủ các tầng nghĩa', (tester) async {
    await _pump(tester, textOf: _multiMeaningTextOf, multiMeaning: true);
    final rendered = _renderedText(tester);
    expect(rendered, contains('Hành'));
    expect(rendered, contains('đi'));
    expect(rendered, contains('bước'));
  });

  // Range map caret→cụm phải đo trên text THẬT SỰ render; đo bằng chuỗi của
  // textOf sẽ lệch dần theo từng cụm (click trúng chữ lại active cụm khác).
  for (final (label, textOf, multiMeaning) in [
    ('một nghĩa', _singleMeaningTextOf, false),
    ('đa nghĩa', _multiMeaningTextOf, true),
  ]) {
    testWidgets('tab $label: click đúng chữ nào active cụm đó', (tester) async {
      final container = await _pump(
        tester,
        textOf: textOf,
        multiMeaning: multiMeaning,
      );
      final target = _renderedText(tester).indexOf('gười'); // giữa chữ "Người"
      expect(target, greaterThan(0));

      final selection = await _tapAtTextOffset(tester, container, target);
      expect(selection, isNotNull);
      expect(selection!.start, 2, reason: 'phải chọn cụm 人, không phải cụm 行');
      expect(selection.word, '人');
    });
  }
}
