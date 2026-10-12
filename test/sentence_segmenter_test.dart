import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/project/domain/sentence_segmenter.dart';

void main() {
  test('split keeps sentence punctuation and newline order', () {
    expect(SentenceSegmenter.split('第一句。\n第二句！\n第三句？'), [
      '第一句。',
      '第二句！',
      '第三句？',
    ]);
  });

  test('split ignores empty whitespace-only segments', () {
    expect(SentenceSegmenter.split('  \n\n  '), isEmpty);
  });
}
