import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/platform_features.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/viet_draft.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/presentation/token_text_view.dart';

const _tokens = [
  Token(
    source: '行',
    sourceStart: 0,
    kind: TokenKind.matched,
    rawValue: 'hành/(2)/đi',
  ),
  Token(source: '。', sourceStart: 1, kind: TokenKind.passthrough),
  Token(source: '人', sourceStart: 2, kind: TokenKind.matched, rawValue: 'người'),
];

Future<ProviderContainer> _pump(WidgetTester tester, PaneId paneId) async {
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
            textOf: (t) => t.displayAllWith(),
            paneId: paneId,
            multiMeaning: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Nhấn giữ (thao tác chọn từ trên cảm ứng) tại ký tự đầu của text hiển thị.
Future<void> _longPressAtStart(WidgetTester tester) async {
  final renderEditable = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  final caret = renderEditable.getLocalRectForCaret(
    const TextPosition(offset: 0),
  );
  await tester.longPressAt(
    renderEditable.localToGlobal(caret.center + const Offset(2, 0)),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => PlatformFeatures.debugIsMobileOverride = null);

  testWidgets(
    'cảm ứng: ô VietPhrase có mục "Chèn vào Bản dịch" và chèn đúng nghĩa',
    (tester) async {
      PlatformFeatures.debugIsMobileOverride = true;
      final container = await _pump(tester, PaneId.vietPhrase);

      await _longPressAtStart(tester);
      expect(find.text('Chèn vào Bản dịch'), findsOneWidget);

      await tester.tap(find.text('Chèn vào Bản dịch'));
      await tester.pumpAndSettle();

      // Nhấn giữ ở đầu chuỗi → nghĩa tầng 1 của token đầu (chữ đầu câu được
      // viết hoa lúc render, chèn vào đúng như đang hiển thị).
      expect(container.read(vietDraftControllerProvider).text, 'Hành');
    },
  );

  testWidgets('cảm ứng: ô Nguồn KHÔNG có mục "Chèn vào Bản dịch"', (
    tester,
  ) async {
    PlatformFeatures.debugIsMobileOverride = true;
    await _pump(tester, PaneId.source);

    await _longPressAtStart(tester);
    expect(find.text('Chèn vào Bản dịch'), findsNothing);
  });

  testWidgets('desktop: không thêm mục cảm ứng (đã có chuột phải)', (
    tester,
  ) async {
    PlatformFeatures.debugIsMobileOverride = false;
    await _pump(tester, PaneId.vietPhrase);

    await _longPressAtStart(tester);
    expect(find.text('Chèn vào Bản dịch'), findsNothing);
  });
}
