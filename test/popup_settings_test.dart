import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/domain/lookup_dictionary_type.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  test('popup tách riêng Nhật/Trung, độc lập tắt/mở và giới hạn 1 loại', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final settings = container.read(settingsProvider);
    expect(settings.popupDictionaryTypesFor(TranslationMode.japanese), isEmpty);
    expect(settings.popupDictionaryTypesFor(TranslationMode.chinese), [
      LookupDictionaryType.lacViet,
    ]);

    // Kiểm tra danh sách khả dụng
    expect(
      availablePopupDictionariesFor(TranslationMode.japanese),
      isNot(contains(LookupDictionaryType.zhVi)),
    );
    expect(
      availablePopupDictionariesFor(TranslationMode.chinese),
      isNot(contains(LookupDictionaryType.jaVi)),
    );
    expect(
      availablePopupDictionariesFor(TranslationMode.chinese),
      isNot(contains(LookupDictionaryType.mazii)),
    );

    // Tắt popup Trung (truyền rỗng)
    await container.read(settingsProvider.notifier).setPopupDictionaryTypes(
      TranslationMode.chinese,
      const [],
    );

    final updated = container.read(settingsProvider);
    expect(updated.popupDictionaryTypesFor(TranslationMode.japanese), isEmpty);
    expect(updated.popupDictionaryTypesFor(TranslationMode.chinese), isEmpty);

    // Bật popup Nhật với VietPhrase, thử chọn zhVi bị lọc bỏ
    await container.read(settingsProvider.notifier).setPopupDictionaryTypes(
      TranslationMode.japanese,
      const [LookupDictionaryType.zhVi, LookupDictionaryType.vietPhrase],
    );

    final updated2 = container.read(settingsProvider);
    expect(updated2.popupDictionaryTypesFor(TranslationMode.japanese), [
      LookupDictionaryType.vietPhrase,
    ]);
  });

  test('tốc độ đọc TTS tách riêng Nhật và Trung', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(settingsProvider).ttsSpeechRateFor(TranslationMode.japanese), 0.5);
    expect(container.read(settingsProvider).ttsSpeechRateFor(TranslationMode.chinese), 0.5);

    await container.read(settingsProvider.notifier).setTtsSpeechRate(
      TranslationMode.japanese,
      0.8,
    );
    await container.read(settingsProvider.notifier).setTtsSpeechRate(
      TranslationMode.chinese,
      0.3,
    );

    final settings = container.read(settingsProvider);
    expect(settings.ttsSpeechRateFor(TranslationMode.japanese), 0.8);
    expect(settings.ttsSpeechRateFor(TranslationMode.chinese), 0.3);
  });
}
