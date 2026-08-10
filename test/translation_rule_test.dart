import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vietyaku/core/app_paths.dart';
import 'package:vietyaku/features/dictionary/domain/dict_type.dart';
import 'package:vietyaku/features/dictionary/domain/phrase_dictionary.dart';
import 'package:vietyaku/features/translation/domain/translation_rule.dart';
import 'package:vietyaku/features/translation/data/translation_rule_repository.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';

PhraseDictionary _dict(DictType type, Map<String, String> entries) =>
    PhraseDictionary(type, entries);

void main() {
  group('parsePostProcessingRules', () {
    test('đọc nhóm, comment và regex có capture', () {
      final document = parsePostProcessingRules(
        r'''
# comment
[Dấu câu]
\s+([,.!?])\s*\t$1
[Xưng hô]
\bta\b\tchúng ta
'''
            .replaceAll(r'\t', '\t'),
      );

      expect(document.errors, isEmpty);
      expect(document.rules, hasLength(2));
      expect(document.rules.first.group, 'Dấu câu');
      expect(document.rules.last.group, 'Xưng hô');
    });

    test('báo regex lỗi nhưng vẫn giữ các rule hợp lệ', () {
      final document = parsePostProcessingRules('[x]\n(\tlỗi\na\tb');

      expect(document.rules, hasLength(1));
      expect(document.errors, hasLength(1));
      expect(document.errors.single.line, 2);
    });

    test('format TAB giữ nguyên một space ở replacement', () {
      final source = '${r'\s+'}\t ';
      final parsed = parsePostProcessingRules(source);

      expect(parsed.rules.single.replacement, ' ');
      expect(
        TranslationRuleEngine(
          postProcessingRules: parsed.rules,
        ).applyPostProcessing('a   b').text,
        'a b',
      );
    });
  });

  group('TranslationRuleEngine hậu xử lý', () {
    test('áp tuần tự một lượt và bung capture replacement', () {
      final first = r'(\w+)\s+ấy\t$1'.replaceAll(r'\t', '\t');
      final second = r'\banh\b\tchàng'.replaceAll(r'\t', '\t');
      final document = parsePostProcessingRules('$first\n$second');
      final result = TranslationRuleEngine(
        postProcessingRules: document.rules,
      ).applyPostProcessing('anh ấy');

      expect(result.text, 'chàng');
      expect(result.matches.map((m) => m.rule.pattern), [
        r'(\w+)\s+ấy',
        r'\banh\b',
      ]);
    });

    test('có thể tắt cả một nhóm', () {
      final document = parsePostProcessingRules('[A]\na\tb\n[B]\nb\tc');
      final result = TranslationRuleEngine(
        postProcessingRules: document.rules,
      ).applyPostProcessing('a', disabledGroups: {'B'});

      expect(result.text, 'b');
      expect(result.matches, hasLength(1));
    });
  });

  group('Luật Nhân', () {
    final rules = parsePersonRules('''
把{0}挡住=ngăn cản {0}
{0}的父亲=phụ thân của {0}
''').rules;

    test('placeholder chỉ nhận key trong phạm vi từ điển cho phép', () {
      final engine = TranslationRuleEngine(personRules: rules);
      final pronouns = _dict(DictType.pronouns, {'他': 'hắn'});

      final match = engine.matchPersonRuleAt('把他挡住', 0, [pronouns]);

      expect(match, isNotNull);
      expect(match!.length, 4);
      expect(match.value, 'ngăn cản hắn');
      expect(match.rule.pattern, '把{0}挡住');
      expect(engine.matchPersonRuleAt('把龙挡住', 0, [pronouns]), isNull);
    });

    test('capture dùng nghĩa đầu và không gọi đệ quy', () {
      final engine = TranslationRuleEngine(personRules: rules);
      final names = _dict(DictType.names, {'田中': 'Tanaka/Điền Trung'});

      final match = engine.matchPersonRuleAt('田中的父亲', 0, [names]);

      expect(match!.value, 'phụ thân của Tanaka');
    });

    test('cụm dài hơn thắng, cùng độ dài giữ thứ tự file', () {
      final engine = TranslationRuleEngine(
        personRules: parsePersonRules('''
把{0}=coi {0}
把{0}挡住=ngăn cản {0}
''').rules,
      );
      final pronouns = _dict(DictType.pronouns, {'他': 'hắn'});

      expect(
        engine.matchPersonRuleAt('把他挡住', 0, [pronouns])!.value,
        'ngăn cản hắn',
      );
    });

    test('bộ LuatNhan bundle đọc sạch và có đủ hơn 200 rule', () {
      final source = File('data/cn/LuatNhan.txt').readAsStringSync();
      final document = parsePersonRules(source);

      expect(document.errors, isEmpty);
      expect(document.rules.length, greaterThanOrEqualTo(200));
    });
  });

  test('TranslationRuleRepository lưu file atomic theo mode', () async {
    final temp = Directory.systemTemp.createTempSync('vietyaku_rules_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths = AppPaths(temp);
    await paths.rulesDir.create(recursive: true);
    final repository = TranslationRuleRepository(paths);

    await repository.savePostProcessing(
      TranslationMode.chinese,
      '[Dấu câu]\na => b',
      disabledGroups: {'Dấu câu'},
    );
    final loaded = await repository.loadPostProcessing(TranslationMode.chinese);

    expect(loaded.document.rules, hasLength(1));
    expect(loaded.document.source, '[Dấu câu]\na => b');
    expect(loaded.disabledGroups, {'Dấu câu'});
    expect(File('${loaded.path}.tmp').existsSync(), isFalse);
    expect(File('${loaded.path}.bak').existsSync(), isFalse);
    expect(p.basename(loaded.path), 'PostProcessing_chinese.txt');
  });
}
