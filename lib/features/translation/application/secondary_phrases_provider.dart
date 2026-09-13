import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../domain/secondary_phrase.dart';
import '../domain/translation_engine.dart';
import 'translation_controller.dart';

/// Các cụm chỉ có trong từ điển phụ (Lạc Việt > Nhật Việt > Mazii > Online >
/// AI) của lượt dịch hiện tại — chỉ mode Nhật. Dùng để mở rộng vùng chọn khi
/// click (tra được nghĩa của cả cụm trong ô Nghĩa).
final secondaryPhrasesProvider = Provider<List<SecondaryPhrase>>(
  (ref) => _phrasesFor(ref, lacVietOnly: false),
);

/// Cụm dùng để ĐÁNH DẤU trong ô VietPhrase (sát khoảng cách / in nghiêng) —
/// CHỈ Lạc Việt. Nhật Việt/Mazii/Online/AI chứa rất nhiều mục kana ngắn nên
/// ghép theo chúng cắt sai ngay giữa từ (`さから` → `さか ら` vì Mazii có `さか`),
/// làm người đọc tưởng đó là ranh giới từ thật.
final vietPhrasePaneSecondaryPhrasesProvider = Provider<List<SecondaryPhrase>>(
  (ref) => _phrasesFor(ref, lacVietOnly: true),
);

List<SecondaryPhrase> _phrasesFor(Ref ref, {required bool lacVietOnly}) {
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
    jaVi: lacVietOnly ? null : dicts.jaVi,
    mazii: lacVietOnly ? null : dicts.mazii,
    onlineDict: lacVietOnly ? null : dicts.onlineDict,
    aiDict: lacVietOnly ? null : dicts.aiDict,
  );
}
