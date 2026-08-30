import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/app.dart';
import 'package:vietyaku/core/platform_features.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VietYakuApp(),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => PlatformFeatures.debugIsMobileOverride = null);

  group('homeDestinations', () {
    test('desktop có đủ 5 tab, EPUB đứng cuối', () {
      PlatformFeatures.debugIsMobileOverride = false;
      expect(homeDestinations().map((d) => d.label), [
        'Dịch',
        'Tìm kiếm',
        'Giao diện',
        'Cài đặt',
        'EPUB',
      ]);
    });

    test('mobile ẩn EPUB (cần hộp thoại lưu file kiểu desktop)', () {
      PlatformFeatures.debugIsMobileOverride = true;
      expect(homeDestinations().map((d) => d.label), [
        'Dịch',
        'Tìm kiếm',
        'Giao diện',
        'Cài đặt',
      ]);
    });
  });

  group('HomeShell chọn bố cục theo bề rộng', () {
    testWidgets('màn rộng → NavigationRail', (tester) async {
      await _pumpShell(tester, const Size(1200, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('màn hẹp (điện thoại) → NavigationBar dưới đáy', (
      tester,
    ) async {
      await _pumpShell(tester, const Size(411, 891));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('ngay dưới ngưỡng vẫn là bố cục hẹp', (tester) async {
      await _pumpShell(tester, const Size(compactWidthBreakpoint - 1, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('đúng ngưỡng đã là bố cục rộng', (tester) async {
      await _pumpShell(tester, const Size(compactWidthBreakpoint, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });

  group('màn Dịch đổi bố cục theo bề rộng', () {
    testWidgets('màn hẹp → 5 tab phẳng, không còn ô chia đôi lồng nhau', (
      tester,
    ) async {
      await _pumpShell(tester, const Size(411, 891));

      for (final label in [
        'Nguồn',
        'Hán Việt',
        'VietPhrase',
        'Nghĩa',
        'Bản dịch',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'thiếu tab "$label"');
      }
      // Chip "Nhật → Việt" bị bỏ trên màn hẹp để 3 nút thao tác lọt màn hình.
      expect(find.text('Nhật → Việt'), findsNothing);
    });

    testWidgets('màn rộng → giữ tabs Nguồn/Hán Việt của bố cục 2 cột', (
      tester,
    ) async {
      await _pumpShell(tester, const Size(1200, 800));

      expect(find.text('Nguồn'), findsOneWidget);
      expect(find.text('Hán Việt'), findsOneWidget);
      expect(find.text('Nhật → Việt'), findsOneWidget);
      // "VietPhrase" ở bố cục rộng chỉ xuất hiện dưới dạng tab con của
      // ResultPane ("VietPhrase một nghĩa" / "VietPhrase (đa nghĩa)"),
      // không phải một tab chính tên đúng "VietPhrase".
      expect(find.text('VietPhrase'), findsNothing);
    });
  });

  testWidgets('mọi tab đều vẽ được ở kích thước điện thoại, không overflow', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(411, 891));

    expect(tester.takeException(), isNull, reason: 'tab Dịch vẽ lỗi ở 411dp');

    for (final label in ['Tìm kiếm', 'Giao diện', 'Cài đặt', 'Dịch']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.takeException(),
        isNull,
        reason: 'tab "$label" vẽ lỗi ở 411dp (thường là RenderFlex overflow)',
      );
    }
  });

  group('nút Back trên màn hẹp', () {
    int selectedTab(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    testWidgets('ở tab phụ thì Back quay về tab Dịch, không thoát app', (
      tester,
    ) async {
      await _pumpShell(tester, const Size(411, 891));

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump(const Duration(milliseconds: 50));
      expect(selectedTab(tester), 3);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));
      expect(selectedTab(tester), 0);
    });

    testWidgets('ở tab Dịch thì Back không đổi tab (để hệ thống thoát app)', (
      tester,
    ) async {
      await _pumpShell(tester, const Size(411, 891));
      expect(selectedTab(tester), 0);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));
      expect(selectedTab(tester), 0);
    });
  });
}
