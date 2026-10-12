import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/project/presentation/project_screen.dart';

void main() {
  testWidgets('project screen shows open action and empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProjectScreen())),
    );

    expect(find.text('Mở file TXT'), findsOneWidget);
    expect(find.text('Chưa mở project'), findsOneWidget);
  });
}
