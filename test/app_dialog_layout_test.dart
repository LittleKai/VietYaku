import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/core/theme/app_theme.dart';
import 'package:vietyaku/shared/widgets/app_dialog.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final size in const [
      Size(390, 844),
      Size(844, 390),
      Size(1200, 760),
    ]) {
      for (final largeText in [false, true]) {
        testWidgets('dialog $brightness $size chữ lớn=$largeText', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = largeText
              ? 2
              : 1;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final fontScale = largeText ? 1.4 : 1.0;
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.light
                  ? AppTheme.light(fontScale: fontScale)
                  : AppTheme.dark(fontScale: fontScale),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      icon: Icons.edit,
                      title: 'Sửa từ điển Nhật – Việt',
                      description: 'Kiểm tra nghĩa trước khi lưu từ.',
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 30; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('Nghĩa $i: 覚悟 — giác ngộ'),
                            ),
                          const Text('Cuối nội dung'),
                        ],
                      ),
                      actionsBuilder: (dialogContext) => [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Hủy'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Lưu từ'),
                        ),
                      ],
                    ),
                    child: const Text('Mở'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Mở'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final dialog = tester.getRect(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Material && widget.type == MaterialType.card,
              ),
            ),
          );
          expect((Offset.zero & size).contains(dialog.topLeft), isTrue);
          expect((Offset.zero & size).contains(dialog.bottomRight), isTrue);
          for (final label in ['Hủy', 'Lưu từ']) {
            final action = find.widgetWithText(
              label == 'Hủy' ? TextButton : FilledButton,
              label,
            );
            final bounds = tester.getRect(action);
            expect(dialog.contains(bounds.topLeft), isTrue);
            expect(dialog.contains(bounds.bottomRight), isTrue);
            expect(action.hitTestable(), findsOneWidget);
          }

          final scrollable = find.descendant(
            of: find.byType(AppDialog),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.text('Cuối nội dung'),
            200,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byType(SingleChildScrollView));
          final lastLine = tester.getRect(find.text('Cuối nội dung'));
          expect(viewport.inflate(0.01).contains(lastLine.topLeft), isTrue);
          expect(viewport.inflate(0.01).contains(lastLine.bottomRight), isTrue);
          await tester.tap(find.text('Hủy'));
          await tester.pumpAndSettle();
          expect(find.byType(AppDialog), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
