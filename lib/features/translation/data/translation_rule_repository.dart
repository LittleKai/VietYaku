import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';
import '../domain/translation_engine.dart';
import '../domain/translation_rule.dart';

class TranslationRuleFile {
  final String path;
  final RuleDocument<RegexTranslationRule> document;
  final Set<String> disabledGroups;

  const TranslationRuleFile(this.path, this.document, this.disabledGroups);
}

class TranslationRuleRepository {
  final AppPaths paths;

  const TranslationRuleRepository(this.paths);

  String postProcessingPath(TranslationMode mode) =>
      p.join(paths.rulesDir.path, 'PostProcessing_${mode.name}.txt');

  String disabledGroupsPath(TranslationMode mode) =>
      p.join(paths.rulesDir.path, 'PostProcessing_${mode.name}.disabled.txt');

  Future<TranslationRuleFile> loadPostProcessing(TranslationMode mode) async {
    final path = postProcessingPath(mode);
    final file = File(path);
    final source = await file.exists() ? await file.readAsString() : '';
    final disabledFile = File(disabledGroupsPath(mode));
    final disabled = await disabledFile.exists()
        ? (await disabledFile.readAsLines())
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toSet()
        : <String>{};
    return TranslationRuleFile(
      path,
      parsePostProcessingRules(source),
      disabled,
    );
  }

  Future<void> savePostProcessing(
    TranslationMode mode,
    String source, {
    Set<String> disabledGroups = const {},
  }) async {
    await paths.rulesDir.create(recursive: true);
    await _atomicWrite(File(postProcessingPath(mode)), source);
    final disabled = disabledGroups.toList()..sort();
    await _atomicWrite(File(disabledGroupsPath(mode)), disabled.join('\n'));
  }

  Future<void> _atomicWrite(File target, String source) async {
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    final sink = temporary.openWrite();
    sink.write(source);
    await sink.flush();
    await sink.close();
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }
}
