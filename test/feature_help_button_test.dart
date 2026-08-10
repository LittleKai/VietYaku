import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/shared/widgets/feature_help_button.dart';

void main() {
  testWidgets('nút trợ giúp mở dialog giải thích và đóng được', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeatureHelpButton(
            title: 'Giải thích Search Center',
            summary: 'Tóm tắt tính năng.',
            points: ['Exact', 'Wildcard', 'Full-text'],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('Giải thích Search Center'), findsOneWidget);
    expect(find.text('Wildcard'), findsOneWidget);

    await tester.tap(find.text('Đã hiểu'));
    await tester.pumpAndSettle();
    expect(find.text('Giải thích Search Center'), findsNothing);
  });
}
