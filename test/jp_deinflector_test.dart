import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/translation/domain/jp_deinflector.dart';

JapaneseDeinflectionCandidate? candidateFor(String surface, String lemma) {
  for (final candidate in JapaneseDeinflector.deinflect(surface)) {
    if (candidate.lemma == lemma) return candidate;
  }
  return null;
}

void main() {
  test('handles common た forms', () {
    expect(candidateFor('食べた', '食べる')?.rules, contains('past-ta'));
    expect(candidateFor('行った', '行く')?.rules, contains('past-ta-kana'));
  });

  test('handles common ない forms', () {
    expect(candidateFor('食べない', '食べる')?.rules, contains('negative-nai'));
    expect(candidateFor('行かない', '行く')?.rules, contains('negative-nai'));
  });

  test('handles common て forms', () {
    expect(candidateFor('食べて', '食べる')?.rules, contains('te-form'));
    expect(candidateFor('読んで', '読む')?.rules, contains('te-form-nasal'));
  });

  test('handles passive and causative forms', () {
    expect(candidateFor('食べられた', '食べる')?.rules, contains('passive'));
    expect(candidateFor('読まれた', '読む')?.rules, contains('passive'));
    expect(candidateFor('食べさせた', '食べる')?.rules, contains('causative'));
    expect(candidateFor('読ませた', '読む')?.rules, contains('causative'));
  });

  test('surfaceLength is UTF-16 length and rules are immutable', () {
    final candidate = candidateFor('食べた', '食べる')!;
    expect(candidate.surfaceLength, '食べた'.length);
    expect(() => candidate.rules.add('mutate'), throwsUnsupportedError);
  });
}
