import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/dictionary/domain/entry_impact.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

void main() {
  test('đếm occurrence chồng lấn trong văn bản đang mở', () {
    expect(countOccurrences('哈哈哈', '哈哈'), 2);
  });

  test('preview hiện đủ base, shared, new và số lần tác động', () {
    final impact = previewEntryImpact(
      rawKey: '少女',
      rawMeaning: 'thiếu nữ mới',
      sourceText: '少女と少女',
      mode: TranslationMode.japanese,
      baseValue: 'thiếu nữ',
      currentLayerValue: 'cô gái',
    );
    expect(impact.baseValue, 'thiếu nữ');
    expect(impact.currentLayerValue, 'cô gái');
    expect(impact.occurrences, 2);
    expect(impact.canSave, isTrue);
  });

  test('chặn key phá format và cảnh báo sai script theo mode', () {
    final impact = previewEntryImpact(
      rawKey: 'テスト=壊',
      rawMeaning: 'test',
      sourceText: '',
      mode: TranslationMode.chinese,
    );
    expect(impact.canSave, isFalse);
    expect(impact.errors, isNotEmpty);
    expect(impact.warnings, contains(contains('Kana')));
  });
}
