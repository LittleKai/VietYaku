import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/dictionary/application/dictionaries_provider.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';
import 'package:vietyaku/features/translation/application/lookup_controller.dart';
import 'package:vietyaku/features/translation/application/token_selection.dart';

/// Bộ dict thay được giữa chừng, mô phỏng `reload()` sau khi tra AI/online ghi
/// thêm mục vào từ điển.
class _MutableDicts extends DictionariesNotifier {
  _MutableDicts(this.loaded);
  LoadedDictionaries loaded;

  @override
  Future<LoadedDictionaries> build() async => loaded;
}

LoadedDictionaries _dicts({
  Map<String, String> vietPhrase = const {},
  Map<String, String> aiDict = const {},
  Map<String, String> aiEntries = const {},
}) {
  PhraseDictionary d(DictType t, Map<String, String> e) => PhraseDictionary(t, e);
  return LoadedDictionaries(
    userDict: d(DictType.userDict, const {}),
    names: d(DictType.names, const {}),
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
    aiDict: d(DictType.aiDict, aiDict),
    aiEntries: d(DictType.aiEntries, aiEntries),
    stats: const {},
  );
}

void main() {
  Future<(ProviderContainer, _MutableDicts)> setUpContainer(
    LoadedDictionaries initial,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = _MutableDicts(initial);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dictionariesProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(dictionariesProvider.future);
    return (container, notifier);
  }

  test('refreshCurrent hiện mục vừa ghi vào VietPhrase/AiEntries/AiDict', () async {
    final (container, notifier) = await setUpContainer(_dicts());
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('背徳');
    expect(container.read(lookupControllerProvider)!.sections, isEmpty);

    // Tra AI xong: overlay VietPhrase + AiEntries + AiDict đều có thêm mục.
    notifier.loaded = _dicts(
      vietPhrase: const {'背徳': 'phản bội đạo đức'},
      aiDict: const {'背徳': '<<AI Dịch>>\n{"meaning":"phản bội đạo đức"}'},
      aiEntries: const {'背徳': 'phản bội đạo đức'},
    );
    await container.read(dictionariesProvider.notifier).reload();
    lookup.refreshCurrent();

    final labels = container
        .read(lookupControllerProvider)!
        .sections
        .map((s) => s.label)
        .toSet();
    expect(labels, containsAll(<String>['VietPhrase', 'AI Dịch', 'AI tách từ']));
  });

  test('refreshCurrent giữ mục chỉ có trong phiên (nghĩa máy dịch)', () async {
    final (container, notifier) = await setUpContainer(_dicts());
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('背徳');
    lookup.addOnlineSections('背徳', const [
      LookupSection('背徳', 'Google Việt', 'bội đức'),
    ]);

    notifier.loaded = _dicts(vietPhrase: const {'背徳': 'phản bội đạo đức'});
    await container.read(dictionariesProvider.notifier).reload();
    lookup.refreshCurrent();

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => s.label), contains('VietPhrase'));
    expect(
      sections.singleWhere((s) => s.label == 'Google Việt').body,
      equals('bội đức'),
      reason: 'nghĩa máy dịch không được lưu vào từ điển nên tra lại sẽ mất',
    );
  });

  test('refreshCurrent bỏ mục vừa bị xóa khỏi từ điển', () async {
    final (container, notifier) = await setUpContainer(
      _dicts(vietPhrase: const {'背徳': 'phản bội đạo đức'}),
    );
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('背徳');
    expect(
      container.read(lookupControllerProvider)!.sections.map((s) => s.label),
      contains('VietPhrase'),
    );

    // Xóa từ: mục cũ KHÔNG được ghép lại, nếu không ô Nghĩa vẫn hiện
    // nghĩa vừa bị gỡ khỏi từ điển.
    notifier.loaded = _dicts();
    await container.read(dictionariesProvider.notifier).reload();
    lookup.refreshCurrent();

    expect(container.read(lookupControllerProvider)!.sections, isEmpty);
  });

  test('refreshCurrent không làm gì khi ô Nghĩa đang trống', () async {
    final (container, _) = await setUpContainer(_dicts());
    container.read(lookupControllerProvider.notifier).refreshCurrent();
    expect(container.read(lookupControllerProvider), isNull);
  });

  test('Hiển thị AI Dịch (Cả câu) khi câu chứa từ tra đã có trong AiDict', () async {
    const fullSentence = '彼が言ったことは本当だった。';
    final (container, _) = await setUpContainer(
      _dicts(
        vietPhrase: const {'言った': 'đã nói'},
        aiDict: const {
          fullSentence:
              '<<AI Dịch>>\n{"meaning":"Những điều anh ấy nói là sự thật."}',
        },
      ),
    );
    final lookup = container.read(lookupControllerProvider.notifier);

    lookup.lookup('言った', rawEnclosingSentence: fullSentence);

    final sections = container.read(lookupControllerProvider)!.sections;
    expect(sections.map((s) => s.label), containsAll(['VietPhrase', 'AI Dịch (Cả câu)']));

    final sentenceSection = sections.singleWhere((s) => s.label == 'AI Dịch (Cả câu)');
    expect(sentenceSection.word, equals(fullSentence));
    expect(sentenceSection.body, contains('Những điều anh ấy nói là sự thật.'));
  });

  test('enclosingSentenceAt trích xuất đúng câu và nhận diện từ điển AiDict', () {
    const text = 'こんにちは。彼が言ったことは本当だった。信じられない！';
    final dicts = _dicts(
      aiDict: const {
        '彼が言ったことは本当だった。':
            '<<AI Dịch>>\n{"meaning":"Những điều anh ấy nói là sự thật."}',
      },
    );

    // Vị trí "言った" (khoảng index 9-11)
    final sent = enclosingSentenceAt(text, 9, 11, dicts: dicts);
    expect(sent, equals('彼が言ったことは本当だった。'));
  });
}

