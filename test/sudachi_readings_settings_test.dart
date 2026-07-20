import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/application/translation_controller.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/domain/reading_extractor.dart';

class MockDictionariesNotifier extends DictionariesNotifier {
  final LoadedDictionaries data;
  MockDictionariesNotifier(this.data);

  @override
  Future<LoadedDictionaries> build() async => data;
}

LoadedDictionaries _createMock({
  required PhraseDictionary jaVi,
  required PhraseDictionary lacViet,
  required PhraseDictionary sudachiReadings,
}) {
  final empty = PhraseDictionary(DictType.vietPhrase, const {});
  return LoadedDictionaries(
    userDict: empty,
    names: empty,
    vietPhrase: empty,
    lacViet: lacViet,
    chinesePhienAm: empty,
    pronouns: empty,
    babylon: empty,
    thieuChuu: empty,
    cedict: empty,
    chinesePhienAmEnglish: empty,
    jaVi: jaVi,
    zhVi: empty,
    sudachiReadings: sudachiReadings,
    stats: const {},
  );
}

void main() {
  group('SudachiReadingsMode lookup prioritization', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('Japanese mode lookup - prioritization options', () async {
      final mockData1 = _createMock(
        jaVi: PhraseDictionary(DictType.jaVi, {
          '覇権': '{はけん} bá quyền',
        }),
        lacViet: PhraseDictionary(DictType.lacViet, {
          '覇権': '(haken) bá quyền',
        }),
        sudachiReadings: PhraseDictionary(DictType.jaVi, {
          '覇権': 'ハケン',
        }),
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(() => MockDictionariesNotifier(mockData1)),
        ],
      );

      addTearDown(container.dispose);

      // Force initialize currentModeProvider to japanese
      container.read(currentModeProvider.notifier).state = TranslationMode.japanese;

      // Await future to ensure provider state is AsyncData
      await container.read(dictionariesProvider.future);

      // 1. Test sudachiFirst (Default)
      // SudachiReadings should win over jaVi and lacViet
      container.read(lookupControllerProvider.notifier).lookup('覇権');
      LookupResult? result = container.read<LookupResult?>(lookupControllerProvider);
      expect(result, isNotNull);
      expect(result!.reading, 'ハケン');
      expect(result.readingKind, ReadingKind.kana);

      // 2. Test jaViFirst (like current)
      // jaVi's kana {はけん} should win over Sudachi's ハケン
      await container.read(settingsProvider.notifier).setSudachiReadings(SudachiReadingsMode.jaViFirst);
      container.read(lookupControllerProvider.notifier).lookup('覇権');
      result = container.read<LookupResult?>(lookupControllerProvider);
      expect(result, isNotNull);
      expect(result!.reading, 'はけん');
      expect(result.readingKind, ReadingKind.kana);

      // 3. Test disabled
      // jaVi's kana {はけん} should win, and Sudachi should be skipped. Let's verify when jaVi has no reading.
      final mockData2 = _createMock(
        jaVi: PhraseDictionary(DictType.jaVi, {
          '覇権': 'bá quyền', // no reading in jaVi
        }),
        lacViet: PhraseDictionary(DictType.lacViet, {
          '覇権': '(haken) bá quyền',
        }),
        sudachiReadings: PhraseDictionary(DictType.jaVi, {
          '覇権': 'ハケン',
        }),
      );

      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dictionariesProvider.overrideWith(() => MockDictionariesNotifier(mockData2)),
        ],
      );
      addTearDown(container2.dispose);
      container2.read(currentModeProvider.notifier).state = TranslationMode.japanese;

      // Await future for container2
      await container2.read(dictionariesProvider.future);

      // Under disabled mode, it should fallback to lacViet's haken instead of Sudachi's ハケン
      await container2.read(settingsProvider.notifier).setSudachiReadings(SudachiReadingsMode.disabled);
      container2.read(lookupControllerProvider.notifier).lookup('覇権');
      result = container2.read<LookupResult?>(lookupControllerProvider);
      expect(result, isNotNull);
      expect(result!.reading, 'haken');
      expect(result.readingKind, ReadingKind.romaji);
    });
  });
}
