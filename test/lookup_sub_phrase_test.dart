import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';

class _FakeDictsNotifier extends DictionariesNotifier {
  _FakeDictsNotifier(this.loaded);
  final LoadedDictionaries loaded;

  @override
  Future<LoadedDictionaries> build() async => loaded;
}

LoadedDictionaries _createDicts({
  Map<String, String> userDict = const {},
  Map<String, String> names = const {},
  Map<String, String> vietPhrase = const {},
}) {
  PhraseDictionary d(DictType t, Map<String, String> e) => PhraseDictionary(t, e);
  return LoadedDictionaries(
    userDict: d(DictType.userDict, userDict),
    names: d(DictType.names, names),
    vietPhrase: d(DictType.vietPhrase, vietPhrase),
    lacViet: d(DictType.lacViet, const {}),
    chinesePhienAm: d(DictType.chinesePhienAm, const {}),
    pronouns: d(DictType.pronouns, const {}),
    babylon: d(DictType.babylon, const {}),
    thieuChuu: d(DictType.thieuChuu, const {}),
    cedict: d(DictType.cedict, const {}),
    chinesePhienAmEnglish: d(DictType.chinesePhienAmEnglish, const {}),
    jaVi: d(DictType.jaVi, const {}),
    zhVi: d(DictType.zhVi, const {}),
    aiDict: d(DictType.aiDict, const {}),
    aiEntries: d(DictType.aiEntries, const {}),
    stats: const {},
  );
}

void main() {
  Future<ProviderContainer> setUpContainer(LoadedDictionaries dicts) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(() => _FakeDictsNotifier(dicts)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(dictionariesProvider.future);
    return container;
  }

  test('Tra cứu cụm từ hiển thị đầy đủ cả cụm lớn và các cụm vietphrase nhỏ hơn bên trong', () async {
    final dicts = _createDicts(
      vietPhrase: const {
        '神眷之力': 'thần quyến chi lực',
        '神眷': 'thần quyến',
        '之力': 'lực lượng',
      },
    );
    final container = await setUpContainer(dicts);
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('神眷之力');

    final sections = container.read(lookupControllerProvider)!.sections;
    final vpSections = sections.where((s) => s.label == 'VietPhrase').toList();

    // Phải hiển thị đầy đủ cả cụm '神眷之力' và các cụm con '神眷', '之力'
    expect(vpSections.map((s) => s.word).toList(), [
      '神眷之力',
      '神眷',
      '之力',
    ]);
    expect(vpSections[0].body, 'thần quyến chi lực');
    expect(vpSections[1].body, 'thần quyến');
    expect(vpSections[2].body, 'lực lượng');
  });

  test('Cụm con nằm trong UserDict hoặc Names vẫn nhận diện đúng nhãn từ điển', () async {
    final dicts = _createDicts(
      vietPhrase: const {
        '神眷之力': 'thần quyến chi lực',
      },
      userDict: const {
        '神眷': 'thần quyến (user)',
      },
      names: const {
        '之力': 'Chi Lực',
      },
    );
    final container = await setUpContainer(dicts);
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('神眷之力');

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => (s.word, s.label, s.body)).toList(), [
      ('神眷之力', 'VietPhrase', 'thần quyến chi lực'),
      ('神眷', 'UserDict', 'thần quyến (user)'),
      ('之力', 'Names', 'Chi Lực'),
    ]);
  });

  test('Cụm lớn không có trong từ điển nhưng chứa các cụm con thì vẫn hiển thị các cụm con', () async {
    final dicts = _createDicts(
      vietPhrase: const {
        '神眷': 'thần quyến',
        '之力': 'lực lượng',
      },
    );
    final container = await setUpContainer(dicts);
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('神眷之力');

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => s.word).toList(), [
      '神眷',
      '之力',
    ]);
  });

  test('Không bị trùng lặp khi cụm con lặp lại trong chuỗi', () async {
    final dicts = _createDicts(
      vietPhrase: const {
        '嘻嘻': 'hi hi',
        '哈哈': 'ha ha',
      },
    );
    final container = await setUpContainer(dicts);
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('嘻嘻哈哈嘻嘻');

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => s.word).toList(), [
      '嘻嘻',
      '哈哈',
    ]);
  });
}
