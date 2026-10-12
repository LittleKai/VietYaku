import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/translation/domain/meaning_choice.dart';

void main() {
  test('flatten tiered VietPhrase value into clean 1-based choices', () {
    expect(
      meaningChoicesFromValue('(n)/ký ức/hồi ức/(2)/(v)/nhớ lại'),
      ['ký ức', 'hồi ức', 'nhớ lại'],
    );
  });

  test('empty or marker-only value has no choices', () {
    expect(meaningChoicesFromValue(''), isEmpty);
    expect(meaningChoicesFromValue('(2)/(v)'), isEmpty);
  });

  test('choiceAt uses one-based keyboard indexes and caps at nine', () {
    const choices = ['một', 'hai'];
    expect(choiceAt(choices, 1), 'một');
    expect(choiceAt(choices, 2), 'hai');
    expect(choiceAt(choices, 0), isNull);
    expect(choiceAt(choices, 3), isNull);
    expect(choiceAt(List<String>.generate(10, (i) => '$i'), 10), isNull);
  });
}
