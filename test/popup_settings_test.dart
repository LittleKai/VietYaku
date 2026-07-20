import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/domain/lookup_dictionary_type.dart';

void main() {
  test('popup mặc định Lạc Việt, cho phép tắt và giới hạn 2 loại', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(settingsProvider).popupDictionaryTypes, [
      LookupDictionaryType.lacViet,
    ]);

    await container
        .read(settingsProvider.notifier)
        .setPopupDictionaryTypes(const []);
    expect(container.read(settingsProvider).popupDictionaryTypes, isEmpty);

    await container
        .read(settingsProvider.notifier)
        .setPopupDictionaryTypes(const [
          LookupDictionaryType.vietPhrase,
          LookupDictionaryType.lacViet,
          LookupDictionaryType.jaVi,
        ]);
    expect(container.read(settingsProvider).popupDictionaryTypes, [
      LookupDictionaryType.vietPhrase,
      LookupDictionaryType.lacViet,
    ]);
  });
}
