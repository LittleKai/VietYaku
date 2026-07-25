import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../domain/secondary_phrase.dart';
import '../domain/translation_engine.dart';
import 'translation_controller.dart';

/// Các cụm chỉ có trong từ điển phụ (Lạc Việt > Nhật Việt > Mazii) của lượt
/// dịch hiện tại — chỉ mode Nhật. Dùng cho mở rộng vùng chọn khi click và cho
/// đánh dấu hiển thị trong ô VietPhrase.
final secondaryPhrasesProvider = Provider<List<SecondaryPhrase>>((ref) {
  final state = ref.watch(translationControllerProvider);
  if (state.mode != TranslationMode.japanese || state.tokens.isEmpty) {
    return const [];
  }
  final dicts = ref.watch(dictionariesProvider).valueOrNull;
  if (dicts == null) return const [];
  return findSecondaryPhrases(
    text: state.sourceText,
    tokens: state.tokens,
    lacViet: dicts.lacViet,
    jaVi: dicts.jaVi,
    mazii: dicts.mazii,
  );
});
