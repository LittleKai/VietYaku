import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/domain/translation_rule.dart';

void main() {
  test('scope Luật Nhân và bật regex được lưu vào settings', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(settingsProvider).personRuleScope,
      PersonRuleScope.off,
    );
    expect(container.read(settingsProvider).postProcessingEnabled, isFalse);

    await container
        .read(settingsProvider.notifier)
        .setPersonRuleScope(PersonRuleScope.pronounsAndNames);
    await container
        .read(settingsProvider.notifier)
        .setPostProcessingEnabled(true);

    expect(
      container.read(settingsProvider).personRuleScope,
      PersonRuleScope.pronounsAndNames,
    );
    expect(container.read(settingsProvider).postProcessingEnabled, isTrue);
    expect(prefs.getString('translate.personRuleScope'), 'pronounsAndNames');
    expect(prefs.getBool('translate.postProcessingEnabled'), isTrue);
  });
}
