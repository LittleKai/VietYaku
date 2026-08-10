import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary_search/domain/dictionary_search.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  final layers = [
    const DictionarySearchLayer(
      id: 'shared',
      label: 'VietPhrase chung',
      type: DictType.vietPhrase,
      entries: {'龍王': 'long vương mới'},
    ),
    const DictionarySearchLayer(
      id: 'base',
      label: 'VietPhrase gốc',
      type: DictType.vietPhrase,
      entries: {'龍': 'rồng', '龍王': 'long vương', '少女': 'thiếu nữ'},
    ),
  ];

  test('exact trả cả overlay và base, chỉ overlay là lớp đang thắng', () {
    final response = searchDictionaryLayers(
      layers,
      const DictionarySearchQuery(
        text: '龍王',
        mode: DictionarySearchMode.exactKey,
      ),
    );
    expect(response.totalMatches, 2);
    expect(response.results.first.isWinningLayer, isTrue);
    expect(response.results.last.isWinningLayer, isFalse);
  });

  test('prefix và wildcard tìm trên key', () {
    final prefix = searchDictionaryLayers(
      layers,
      const DictionarySearchQuery(
        text: '龍',
        mode: DictionarySearchMode.prefixKey,
      ),
    );
    expect(prefix.totalMatches, 3);

    final wildcard = searchDictionaryLayers(
      layers,
      const DictionarySearchQuery(
        text: '*女',
        mode: DictionarySearchMode.wildcardKey,
      ),
    );
    expect(wildcard.results.single.key, '少女');
  });

  test('full-text không phân biệt hoa thường và lọc loại từ điển', () {
    final response = searchDictionaryLayers(
      layers,
      const DictionarySearchQuery(
        text: 'LONG VƯƠNG',
        mode: DictionarySearchMode.fullTextValue,
        dictionaryTypes: {DictType.vietPhrase},
      ),
    );
    expect(response.totalMatches, 2);
  });

  test('isAvailableFor lọc đúng từ điển theo mode ngôn ngữ', () {
    expect(DictType.mazii.isAvailableFor(TranslationMode.japanese), isTrue);
    expect(DictType.jaVi.isAvailableFor(TranslationMode.japanese), isTrue);
    expect(DictType.zhVi.isAvailableFor(TranslationMode.japanese), isFalse);

    expect(DictType.mazii.isAvailableFor(TranslationMode.chinese), isFalse);
    expect(DictType.jaVi.isAvailableFor(TranslationMode.chinese), isFalse);
    expect(DictType.zhVi.isAvailableFor(TranslationMode.chinese), isTrue);

    expect(DictType.vietPhrase.isAvailableFor(TranslationMode.japanese), isTrue);
    expect(DictType.vietPhrase.isAvailableFor(TranslationMode.chinese), isTrue);
  });
}

