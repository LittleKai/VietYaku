import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/glossary/data/glossary_service.dart';
import 'package:vietyaku/features/glossary/data/user_glossary_service.dart';
import 'package:vietyaku/features/glossary/domain/glossary_term.dart';
import 'package:vietyaku/features/glossary/presentation/glossary_update_dialog.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/translation_controller.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

class _WidgetRefContext extends ConsumerWidget {
  const _WidgetRefContext({required this.builder});
  final Widget Function(BuildContext context, WidgetRef ref) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => builder(context, ref);
}

void main() {
  late Directory tempDir;
  late Directory userdataDir;

  setUp(() async {
    GlossaryService.clearCache();
    tempDir = await Directory.systemTemp.createTemp('global_glossary_test');
    userdataDir = await Directory.systemTemp.createTemp('user_glossary_test');
    final jpDir = Directory(p.join(tempDir.path, 'JP'));
    await jpDir.create(recursive: true);
    await File(
      p.join(jpDir.path, GlossaryService.globalGlossaryFileName),
    ).writeAsString(
      '{\r\n'
      '  "name": "Global Glossary",\r\n'
      '  "lang": "JP",\r\n'
      '  "terms": [\r\n'
      '    {\r\n'
      '      "source": "菜畑小鳥",\r\n'
      '      "target": "Nabata Kotori",\r\n'
      '      "kind": "proper_noun",\r\n'
      '      "notes": "",\r\n'
      '      "created_by": "A.I",\r\n'
      '      "date_added": "2026-04-29"\r\n'
      '    }\r\n'
      '  ]\r\n'
      '}',
      encoding: utf8,
    );
  });

  tearDown(() async {
    GlossaryService.clearCache();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    try {
      await userdataDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'showGlossaryUpdateDialog hiện 3 nút với nút User Glossary ở giữa và lưu đúng',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) => AppPaths(userdataDir)),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container
          .read(settingsProvider.notifier)
          .setGlossaryDir(tempDir.path);

      await tester.runAsync(() async {
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: _WidgetRefContext(
                builder: (context, ref) {
                  return ElevatedButton(
                    onPressed: () => showGlossaryUpdateDialog(
                      context,
                      ref,
                      source: '菜畑小鳥',
                      meaning: 'Chim nhỏ trên nương',
                    ),
                    child: const Text('Open Update Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Update Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Cập nhật Global Glossary JP'), findsOneWidget);

      final cancelFinder = find.widgetWithText(TextButton, 'Hủy');
      final userGlossaryFinder = find.widgetWithText(
        FilledButton,
        'Lưu vào User Glossary',
      );
      final globalGlossaryFinder = find.widgetWithText(
        FilledButton,
        'Ghi đè glossary',
      );

      expect(cancelFinder, findsOneWidget);
      expect(userGlossaryFinder, findsOneWidget);
      expect(globalGlossaryFinder, findsOneWidget);

      // Nút User Glossary nằm giữa nút Hủy và Ghi đè glossary theo tọa độ X
      final cancelOffset = tester.getTopLeft(cancelFinder);
      final userOffset = tester.getTopLeft(userGlossaryFinder);
      final globalOffset = tester.getTopLeft(globalGlossaryFinder);

      expect(cancelOffset.dx, lessThan(userOffset.dx));
      expect(userOffset.dx, lessThan(globalOffset.dx));

      // Nút User Glossary có màu sắc khác với nút Ghi đè glossary và chữ trắng tương phản tốt
      final userBtn = tester.widget<FilledButton>(userGlossaryFinder);
      final userBg = userBtn.style?.backgroundColor?.resolve({});
      expect(userBg, const Color(0xFF00897B));
      final userFg = userBtn.style?.foregroundColor?.resolve({});
      expect(userFg, Colors.white);

      // Bấm nút Lưu vào User Glossary
      await tester.tap(userGlossaryFinder);
      await tester.pump();

      // Vòng runAsync / pump xen kẽ để I/O thật và fake async phối hợp
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Dialog đã đóng
      expect(find.text('Cập nhật Glossary JP'), findsNothing);

      GlossaryTerm? savedTerm;
      await tester.runAsync(() async {
        final userService = UserGlossaryService(tempDir.path);
        savedTerm = await userService.find(TranslationMode.japanese, '菜畑小鳥');
      });

      expect(savedTerm, isNotNull);
      expect(savedTerm!.target, 'Chim nhỏ trên nương');

      // File User Glossary.json được tạo đúng chỗ trong thư mục glossary/JP
      final userFile = File(p.join(tempDir.path, 'JP', 'User Glossary.json'));
      expect(userFile.existsSync(), isTrue);

      // Global Glossary trong tempDir KHÔNG bị ghi đè (vẫn giữ "Nabata Kotori")
      GlossaryTerm? globalTerm;
      await tester.runAsync(() async {
        final globalService = GlossaryService(tempDir.path);
        globalTerm = await globalService.find(TranslationMode.japanese, '菜畑小鳥');
      });
      expect(globalTerm, isNotNull);
      expect(globalTerm!.target, 'Nabata Kotori');
    },
  );

  testWidgets(
    'Khi từ đã có trong User Glossary với nghĩa khớp nhưng Global Glossary khác, bấm Ghi đè glossary vẫn ghi đúng vào Global Glossary',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      // Đã có trong User Glossary với nghĩa "Chim nhỏ trên nương"
      await tester.runAsync(() async {
        final userService = UserGlossaryService(tempDir.path);
        await userService.upsert(
          TranslationMode.japanese,
          source: '菜畑小鳥',
          target: 'Chim nhỏ trên nương',
        );
        await GlossaryService(tempDir.path).readAll(TranslationMode.japanese);
      });

      SharedPreferences.setMockInitialValues({'glossary.dir': tempDir.path});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appPathsProvider.overrideWith((ref) => AppPaths(userdataDir)),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentModeProvider.notifier).state =
          TranslationMode.japanese;
      await container
          .read(settingsProvider.notifier)
          .setGlossaryDir(tempDir.path);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: _WidgetRefContext(
                builder: (context, ref) {
                  return ElevatedButton(
                    onPressed: () => showGlossaryUpdateDialog(
                      context,
                      ref,
                      source: '菜畑小鳥',
                      meaning: 'Chim nhỏ trên nương',
                    ),
                    child: const Text('Open Update Dialog 2'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Update Dialog 2'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Bấm nút "Ghi đè glossary" (Global Glossary)
      final globalGlossaryFinder = find.widgetWithText(
        FilledButton,
        'Ghi đè glossary',
      );
      await tester.tap(globalGlossaryFinder);
      await tester.pump();

      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Kiểm tra Global Glossary đã được cập nhật thành "Chim nhỏ trên nương"
      GlossaryTerm? updatedGlobalTerm;
      await tester.runAsync(() async {
        final globalService = GlossaryService(tempDir.path);
        updatedGlobalTerm = await globalService.find(
          TranslationMode.japanese,
          '菜畑小鳥',
        );
      });
      expect(updatedGlobalTerm, isNotNull);
      expect(updatedGlobalTerm!.target, 'Chim nhỏ trên nương');
    },
  );
}
