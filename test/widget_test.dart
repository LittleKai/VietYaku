import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/app.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';

void main() {
  testWidgets('HomeShell shows three navigation destinations', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VietYakuApp(),
    ));
    await tester.pump();

    expect(find.text('Dịch'), findsWidgets);
    expect(find.text('Sửa từ điển'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);
  });
}
