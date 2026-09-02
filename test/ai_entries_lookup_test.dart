import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/domain/lookup_dictionary_type.dart';

class _FakeDicts extends DictionariesNotifier {
  _FakeDicts(this.loaded);
  final LoadedDictionaries loaded;
  @override
  Future<LoadedDictionaries> build() async => loaded;
}

PhraseDictionary _d(DictType t, Map<String, String> e) => PhraseDictionary(t, e);

void main() {
  test('AiEntries ra section trong ô Nghĩa, không chỉ phục vụ engine dịch', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final loaded = LoadedDictionaries(
      userDict: _d(DictType.userDict, const {}),
      names: _d(DictType.names, const {}),
      vietPhrase: _d(DictType.vietPhrase, const {}),
      lacViet: _d(DictType.lacViet, const {}),
      chinesePhienAm: _d(DictType.chinesePhienAm, const {}),
      pronouns: _d(DictType.pronouns, const {}),
      babylon: _d(DictType.babylon, const {}),
      thieuChuu: _d(DictType.thieuChuu, const {}),
      cedict: _d(DictType.cedict, const {}),
      chinesePhienAmEnglish: _d(DictType.chinesePhienAmEnglish, const {}),
      jaVi: _d(DictType.jaVi, const {}),
      zhVi: _d(DictType.zhVi, const {}),
      aiEntries: _d(DictType.aiEntries, {'チャラ': 'lăng nhăng/cợt nhả'}),
      stats: const {},
    );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(() => _FakeDicts(loaded)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(dictionariesProvider.future);

    container.read(lookupControllerProvider.notifier).lookup('チャラ');
    final result = container.read(lookupControllerProvider);
    final section = result!.sections.firstWhere((s) => s.label == 'AI tách từ');

    expect(section.body, contains('lăng nhăng'));
    expect(
      LookupDictionaryType.aiEntries.matchesLabel(section.label),
      isTrue,
      reason: 'phải map được sang loại để bật/tắt trong Cài đặt',
    );
  });
}
