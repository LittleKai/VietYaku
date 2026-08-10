import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../data/translation_rule_repository.dart';
import '../domain/translation_engine.dart';

final postProcessingRuleFileProvider =
    FutureProvider.family<TranslationRuleFile, TranslationMode>((
      ref,
      mode,
    ) async {
      final paths = await ref.watch(appPathsProvider.future);
      return TranslationRuleRepository(paths).loadPostProcessing(mode);
    });
