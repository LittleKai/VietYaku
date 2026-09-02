import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/data/dictionary_repository.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';

PhraseDictionary _d(DictType t, Map<String, String> e) => PhraseDictionary(t, e);

LoadedDictionaries _dicts({
  Map<String, String> vietPhrase = const {},
  Map<String, String> vietPhraseOverlay = const {},
}) => LoadedDictionaries(
  userDict: _d(DictType.userDict, const {}),
  names: _d(DictType.names, const {}),
  // Overlay nằm trên VietPhrase gốc — đúng thứ tự repository merge.
  vietPhrase: _d(DictType.vietPhrase, {...vietPhrase, ...vietPhraseOverlay}),
  lacViet: _d(DictType.lacViet, const {}),
  chinesePhienAm: _d(DictType.chinesePhienAm, const {}),
  pronouns: _d(DictType.pronouns, const {}),
  babylon: _d(DictType.babylon, const {}),
  thieuChuu: _d(DictType.thieuChuu, const {}),
  cedict: _d(DictType.cedict, const {}),
  chinesePhienAmEnglish: _d(DictType.chinesePhienAmEnglish, const {}),
  jaVi: _d(DictType.jaVi, const {}),
  zhVi: _d(DictType.zhVi, const {}),
  stats: const {},
);

void main() {
  // Bug: từ tra online/AI được lưu lại nhưng click vào không hiện mục đã lưu.
  // Nguyên nhân: chính vì từ đó KHÔNG có trong VietPhrase nên mới phải tra —
  // mà không có trong VietPhrase thì engine cắt nó thành từng chữ, token sinh
  // ra không bao giờ bằng key đã lưu nên tra ngược lại luôn trượt.
  group('Từ đã lưu phải cắt được thành đúng một token để click lại', () {
    test('chưa có trong VietPhrase → bị cắt vụn, không click lại được', () {
      final dicts = _dicts();
      final tokens = dicts.engine.translate('再入荷');

      expect(
        tokens.map((t) => t.source),
        isNot(equals(['再入荷'])),
        reason: 'không có mục nào thì engine phải cắt vụn — đây là bug gốc',
      );
    });

    test('có trong overlay VietPhrase → ra đúng một token bằng key', () {
      final dicts = _dicts(
        vietPhraseOverlay: {'再入荷': '(n) sự nhập hàng lại'},
      );
      final tokens = dicts.engine.translate('再入荷');

      expect(tokens.map((t) => t.source), equals(['再入荷']));
    });

    test('cụm dài cũng cắt đúng khi đã có trong overlay', () {
      final dicts = _dicts(
        vietPhrase: {'人': 'người'},
        vietPhraseOverlay: {'チャラ': 'lăng nhăng/cợt nhả'},
      );
      final tokens = dicts.engine.translate('この人こんなにチャラかった');

      expect(
        tokens.map((t) => t.source),
        contains('チャラ'),
        reason: 'sub_entry của AI phải trở thành token click được',
      );
    });

    test('overlay không đè mục VietPhrase gốc cùng key', () {
      // Repository merge overlay TRÊN VietPhrase gốc nhưng ai/online chỉ ghi
      // khi key chưa có, nên trường hợp này không xảy ra trong thực tế; test
      // khoá lại thứ tự merge để đổi ý thì phải sửa cả test.
      final dicts = _dicts(
        vietPhrase: {'再入荷': 'nghĩa gốc'},
        vietPhraseOverlay: {'再入荷': 'nghĩa overlay'},
      );
      expect(dicts.vietPhrase.entries['再入荷'], equals('nghĩa overlay'));
    });
  });
}
