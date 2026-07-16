import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/application/translation_controller.dart';
import 'package:vietyaku/features/translation/presentation/translate_screen.dart';

const sourceDir = r'C:\Users\XEON\My Drive\JP CN Tool\QuickTranslator_Jap';

void main() {
  final available = File('$sourceDir\\VietPhrase.txt').existsSync() &&
      File('$sourceDir\\LacViet.txt').existsSync();

  testWidgets('end-to-end: dịch đoạn Nhật thật, click token ra nghĩa',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final temp = Directory.systemTemp.createTempSync('vy_flow');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths = AppPaths(temp);
    paths.cacheDir.createSync(recursive: true);
    paths.dictionariesDir.createSync(recursive: true);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appPathsProvider.overrideWith((ref) async => paths),
      ],
      child: const MaterialApp(home: Scaffold(body: TranslateScreen())),
    ));

    // Chờ 6 dict load xong trong isolate (cold parse file thật).
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(() => Future.delayed(
          const Duration(milliseconds: 250)));
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'dictionaries phải load xong');

    // Dán đoạn Nhật thật rồi bấm Dịch.
    await tester.enterText(find.byType(TextField).first, '覇権を握る覚悟だ');
    await tester.tap(find.text('Dịch'));
    await tester.pump();

    // Kết quả phải có status line "N token · Xms".
    expect(find.textContaining('token ·'), findsOneWidget);

    // Mô phỏng click token → panel LacViet hiện nghĩa + reading.
    // (`翻译` là entry key lành trong LacViet thật, value có ✚[fānyì].)
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TranslateScreen)));
    container.read(lookupControllerProvider.notifier).lookup('翻译');
    await tester.pump();

    final result = container.read(lookupControllerProvider);
    expect(result, isNotNull);
    expect(result!.found, isTrue, reason: '翻译 phải có trong LacViet');
    expect(result.reading, 'fānyì');
    expect(find.textContaining('dịch'), findsWidgets);

    // Prefix fallback: `覇権を` không có key → lùi dần về `覇権`.
    container.read(lookupControllerProvider.notifier).lookup('覇権を');
    await tester.pump();
    expect(container.read(lookupControllerProvider)!.matchedKey, '覇権');

    // Tab Hán Việt (cột trái): phiên âm toàn văn phải có token.
    await tester.tap(find.text('Hán Việt'));
    await tester.pump();
    final state = container.read(translationControllerProvider);
    expect(state.hanVietTokens, isNotEmpty,
        reason: 'hanVietTokens phải được tính cùng lượt dịch');

    // Tab đa nghĩa (cột phải): đổi tab không dịch lại, token giữ nguyên.
    final tokensBefore = state.tokens;
    await tester.tap(find.text('VietPhrase (đa nghĩa)'));
    await tester.pump();
    expect(
        identical(
            container.read(translationControllerProvider).tokens, tokensBefore),
        isTrue,
        reason: 'đổi tab hiển thị không được re-translate');
  }, skip: !available); // cần dữ liệu QuickTranslator_Jap thật
}
