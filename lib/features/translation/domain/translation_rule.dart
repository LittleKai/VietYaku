import '../../dictionary/domain/phrase_dictionary.dart';
import 'token.dart';

enum PersonRuleScope {
  off,
  pronouns,
  pronounsAndNames,
  pronounsNamesAndVietPhrase,
}

class RuleParseError {
  final int line;
  final String message;

  const RuleParseError(this.line, this.message);
}

class RegexTranslationRule {
  final int line;
  final String group;
  final String pattern;
  final String replacement;
  final RegExp expression;

  const RegexTranslationRule({
    required this.line,
    required this.group,
    required this.pattern,
    required this.replacement,
    required this.expression,
  });
}

class PersonTranslationRule {
  final int line;
  final String pattern;
  final String replacement;
  final String prefix;
  final String suffix;

  const PersonTranslationRule({
    required this.line,
    required this.pattern,
    required this.replacement,
    required this.prefix,
    required this.suffix,
  });

  String replace(String captured) => replacement.replaceAll('{0}', captured);
}

class RuleDocument<T> {
  final String source;
  final List<T> rules;
  final List<RuleParseError> errors;

  const RuleDocument({
    required this.source,
    required this.rules,
    required this.errors,
  });
}

RuleDocument<RegexTranslationRule> parsePostProcessingRules(String source) {
  final rules = <RegexTranslationRule>[];
  final errors = <RuleParseError>[];
  var group = 'Chung';
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index].replaceAll('\r', '');
    if (index == 0 && line.startsWith('\uFEFF')) line = line.substring(1);
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final name = trimmed.substring(1, trimmed.length - 1).trim();
      if (name.isEmpty) {
        errors.add(RuleParseError(index + 1, 'Tên nhóm không được để trống.'));
      } else {
        group = name;
      }
      continue;
    }
    final tab = line.indexOf('\t');
    final arrow = line.indexOf('=>');
    final separator = tab >= 0 ? tab : arrow;
    final separatorLength = tab >= 0 ? 1 : 2;
    if (separator < 0) {
      errors.add(
        RuleParseError(index + 1, 'Rule regex phải dùng TAB hoặc =>.'),
      );
      continue;
    }
    final pattern = line.substring(0, separator).trim();
    final rawReplacement = line.substring(separator + separatorLength);
    // TAB là format chính và giữ nguyên whitespace đích (kể cả đúng 1 space).
    // Cú pháp `=>` thân thiện hơn nên bỏ padding quanh vế đích.
    final replacement = tab >= 0 ? rawReplacement : rawReplacement.trim();
    if (pattern.isEmpty) {
      errors.add(RuleParseError(index + 1, 'Regex không được để trống.'));
      continue;
    }
    try {
      final expression = RegExp(pattern, multiLine: true, unicode: true);
      if (expression.hasMatch('')) {
        errors.add(
          RuleParseError(index + 1, 'Regex không được khớp chuỗi rỗng.'),
        );
        continue;
      }
      rules.add(
        RegexTranslationRule(
          line: index + 1,
          group: group,
          pattern: pattern,
          replacement: replacement,
          expression: expression,
        ),
      );
    } on FormatException catch (error) {
      errors.add(RuleParseError(index + 1, 'Regex không hợp lệ: $error'));
    }
  }
  return RuleDocument(source: source, rules: rules, errors: errors);
}

RuleDocument<PersonTranslationRule> parsePersonRules(String source) {
  final rules = <PersonTranslationRule>[];
  final errors = <RuleParseError>[];
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index].replaceAll('\r', '');
    if (index == 0 && line.startsWith('\uFEFF')) line = line.substring(1);
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator < 0) {
      errors.add(RuleParseError(index + 1, 'Luật Nhân phải dùng dấu =.'));
      continue;
    }
    final pattern = line.substring(0, separator).trim();
    final replacement = line.substring(separator + 1).trim();
    final placeholder = pattern.indexOf('{0}');
    if (placeholder < 0 || pattern.indexOf('{0}', placeholder + 3) >= 0) {
      errors.add(RuleParseError(index + 1, 'Vế nguồn phải có đúng một {0}.'));
      continue;
    }
    if (!replacement.contains('{0}')) {
      errors.add(RuleParseError(index + 1, 'Vế đích phải có {0}.'));
      continue;
    }
    rules.add(
      PersonTranslationRule(
        line: index + 1,
        pattern: pattern,
        replacement: replacement,
        prefix: pattern.substring(0, placeholder),
        suffix: pattern.substring(placeholder + 3),
      ),
    );
  }
  return RuleDocument(source: source, rules: rules, errors: errors);
}

class AppliedRegexRule {
  final RegexTranslationRule rule;
  final int count;

  const AppliedRegexRule(this.rule, this.count);
}

class PostProcessingResult {
  final String text;
  final List<AppliedRegexRule> matches;

  const PostProcessingResult(this.text, this.matches);
}

class PersonRuleMatch {
  final PersonTranslationRule rule;
  final int length;
  final String value;

  const PersonRuleMatch({
    required this.rule,
    required this.length,
    required this.value,
  });
}

/// Engine chung cho rule hậu xử lý và Luật Nhân.
///
/// Regex chạy tuần tự đúng một lượt theo thứ tự file. Luật Nhân chỉ cho `{0}`
/// bắt một key nguyên vẹn từ các từ điển được truyền vào, nên không đệ quy.
class TranslationRuleEngine {
  final List<RegexTranslationRule> postProcessingRules;
  final List<PersonTranslationRule> personRules;

  const TranslationRuleEngine({
    this.postProcessingRules = const [],
    this.personRules = const [],
  });

  PostProcessingResult applyPostProcessing(
    String input, {
    Set<String> disabledGroups = const {},
  }) {
    var output = input;
    final applied = <AppliedRegexRule>[];
    for (final rule in postProcessingRules) {
      if (disabledGroups.contains(rule.group)) continue;
      final matches = rule.expression.allMatches(output).toList();
      if (matches.isEmpty) continue;
      output = output.replaceAllMapped(
        rule.expression,
        (match) => _expandReplacement(rule.replacement, match),
      );
      applied.add(AppliedRegexRule(rule, matches.length));
    }
    return PostProcessingResult(output, applied);
  }

  PersonRuleMatch? matchPersonRuleAt(
    String source,
    int offset,
    List<PhraseDictionary> dictionaries, {
    int? limitEnd,
  }) {
    final end = limitEnd ?? source.length;
    if (personRules.isEmpty || dictionaries.isEmpty || offset >= end) {
      return null;
    }
    PersonRuleMatch? best;
    for (final rule in personRules) {
      if (!source.startsWith(rule.prefix, offset)) continue;
      final captureStart = offset + rule.prefix.length;
      if (captureStart >= end) continue;
      final first = source.codeUnitAt(captureStart);
      var maxLength = 0;
      for (final dictionary in dictionaries) {
        final length = dictionary.maxLenFor(first);
        if (length > maxLength) maxLength = length;
      }
      final maxEnd = end - rule.suffix.length;
      if (maxLength > maxEnd - captureStart) {
        maxLength = maxEnd - captureStart;
      }
      for (var length = maxLength; length >= 1; length--) {
        final captureEnd = captureStart + length;
        if (!source.startsWith(rule.suffix, captureEnd)) continue;
        final key = source.substring(captureStart, captureEnd);
        String? value;
        for (final dictionary in dictionaries) {
          value = dictionary.lookup(key);
          if (value != null) break;
        }
        if (value == null) continue;
        final totalLength = rule.prefix.length + length + rule.suffix.length;
        final candidate = PersonRuleMatch(
          rule: rule,
          length: totalLength,
          value: rule.replace(firstMeaning(value)),
        );
        if (best == null || candidate.length > best.length) best = candidate;
        break;
      }
    }
    return best;
  }
}

String _expandReplacement(String replacement, Match match) {
  return replacement.replaceAllMapped(RegExp(r'\$(?:\{(\d+)\}|(\d+)|\$)'), (
    token,
  ) {
    if (token.group(0) == r'$$') return r'$';
    final rawIndex = token.group(1) ?? token.group(2)!;
    final index = int.parse(rawIndex);
    if (index > match.groupCount) return '';
    return match.group(index) ?? '';
  });
}
