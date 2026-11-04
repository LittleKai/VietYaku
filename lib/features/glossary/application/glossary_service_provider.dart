import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../settings/settings_provider.dart';
import '../data/glossary_service.dart';
import '../data/glossary_term_queue.dart';

/// `GlossaryService` dùng cho MỌI chỗ GHI `Global Glossary.json`.
///
/// Mọi sửa đổi glossary của phiên admin được xếp hàng vào
/// `PendingGlossary_<mode>.txt` và đi lên server cùng lúc bấm Update, để
/// AI_Translation_Bridge trên máy khác kéo về được. Người dùng thường ghi
/// glossary cục bộ như cũ, không xếp hàng gì.
final glossaryServiceProvider = Provider<GlossaryService>((ref) {
  final dir = ref.watch(settingsProvider.select((s) => s.glossaryDir));
  return GlossaryService(
    dir,
    onChanged: (mode, upserts, deletes) async {
      if (!ref.read(dictionarySyncProvider).isAdmin) return;
      final paths = await ref.read(appPathsProvider.future);
      await GlossaryTermQueue(
        paths,
      ).enqueue(mode, upserts: upserts, deletes: deletes);
    },
    onSingleEdit: () async {
      if (!ref.read(dictionarySyncProvider).isAdmin) return;
      // Chỉ sửa lẻ từng từ qua hộp thoại tra từ chính mới tự Update khi đủ
      // ngưỡng (như stageLocalEdit). Mọi thao tác trong màn đồng bộ Glossary ↔
      // VietPhrase (dù 1 hay nhiều mục) dùng upsertAll/removeAll nên chỉ xếp
      // hàng cục bộ, không chặn UI chờ mạng.
      await ref.read(dictionarySyncProvider.notifier).maybeAutoPublish();
    },
  );
});
