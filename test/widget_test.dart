import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/app.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';

void main() {
  testWidgets('HomeShell shows translation, EPUB and settings destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const VietYakuApp(),
      ),
    );
    await tester.pump();

    // "Sửa từ điển" đã chuyển vào tab Cài đặt (không còn là destination riêng).
    expect(find.text('Dịch'), findsWidgets);
    expect(find.text('EPUB'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final labels = rail.destinations
        .map((destination) => (destination.label as Text).data)
        .toList();
    expect(labels, ['Dịch', 'Giao diện', 'Cài đặt', 'EPUB']);
  });
}
