import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/shared/widgets/settings_layout.dart';

void main() {
  testWidgets('SettingsPage Scrollbar luôn gắn vào ScrollPosition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 320,
          child: SettingsPage(
            title: 'Cài đặt',
            description: 'Kiểm tra cuộn',
            children: [
              for (var index = 0; index < 20; index++)
                SizedBox(height: 100, child: Text('Mục $index')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });
}
