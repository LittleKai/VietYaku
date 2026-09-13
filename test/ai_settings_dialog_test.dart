import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/ai_translation/application/ai_settings_controller.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_api_key.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_service_config.dart';
import 'package:vietyaku/features/ai_translation/domain/ai_service_type.dart';
import 'package:vietyaku/features/ai_translation/presentation/ai_settings_dialog.dart';

class _FakeAiSettingsController extends AiSettingsController {
  final AiSettings _initial;
  _FakeAiSettingsController(this._initial);

  @override
  Future<AiSettings> build() async => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('showAiSettingsDialog renders API key list without assertion error', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsWithKey = AiSettings(
      activeService: AiServiceType.geminiCli,
      serviceConfigs: {
        AiServiceType.geminiCli: AiServiceConfig.defaultsFor(AiServiceType.geminiCli).copyWith(
          keys: [AiApiKey('AIzaSyD-fake-key-12345', weight: 2)],
        ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSettingsControllerProvider.overrideWith(
            () => _FakeAiSettingsController(settingsWithKey),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                // Ensure provider is watched so it initializes
                ref.watch(aiSettingsControllerProvider);
                return ElevatedButton(
                  onPressed: () => showAiSettingsDialog(context, ref),
                  child: const Text('Open AI Settings'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open AI Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Danh sách API Keys (1)'), findsOneWidget);
  });
}
