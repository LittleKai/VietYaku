import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../data/glossary_service.dart';
import '../presentation/glossary_update_dialog.dart' show glossaryTargetOf;

/// Chiều đồng bộ giữa Global Glossary (AI_Translation_Bridge) và VietPhrase.
enum GlossarySyncDirection {
  glossaryToVietPhrase('Glossary → VietPhrase'),
  vietPhraseToGlossary('VietPhrase → Glossary');

  const GlossarySyncDirection(this.label);

  final String label;
}

/// Lọc theo việc từ đã có ở bên đích hay chưa.
enum DuplicateFilter {
  notDuplicated('Không trùng'),
  duplicated('Có trùng');

  const DuplicateFilter(this.label);

  final String label;
}

/// Một từ ở bên nguồn kèm giá trị hiện có bên đích (nếu có).
class GlossarySyncRow {
  /// Từ gốc (key VietPhrase / `source` của glossary).
  final String source;

  /// Giá trị sẽ ghi sang bên đích — đúng thứ được ghi, không phải bản rút gọn.
  final String target;

  /// Giá trị đang có bên đích; `null` nghĩa là bên đích chưa có từ này.
  final String? otherTarget;

  /// `created_by` của mục glossary; rỗng khi bên nguồn là VietPhrase.
  final String createdBy;

  const GlossarySyncRow({
    required this.source,
    required this.target,
    required this.otherTarget,
    this.createdBy = '',
  });

  bool get isDuplicate => otherTarget != null;

  /// Đã có bên đích và giá trị y hệt — áp dụng cũng không đổi gì.
  bool get isIdentical => otherTarget == target;

  /// Do A.I sinh ra (glossary dùng "A.I"; chấp nhận cả biến thể "ai").
  bool get isCreatedByAi =>
      const {'a.i', 'ai'}.contains(createdBy.trim().toLowerCase());
}

/// Toàn bộ từ ở bên nguồn của [direction], chưa lọc. Màn hình tự lọc + phân
/// trang trong bộ nhớ vì VietPhrase có hàng trăm nghìn mục.
final glossarySyncRowsProvider = FutureProvider.autoDispose
    .family<List<GlossarySyncRow>, GlossarySyncDirection>((
      ref,
      direction,
    ) async {
      final mode = ref.watch(
        translationControllerProvider.select((state) => state.mode),
      );
      final service = GlossaryService(
        ref.watch(settingsProvider.select((s) => s.glossaryDir)),
      );
      final dicts = await ref.watch(dictionariesProvider.future);
      final vietPhrase = dicts.vietPhrase.entries;
      final glossaryTerms = await service.readAll(mode);

      if (direction == GlossarySyncDirection.glossaryToVietPhrase) {
        return [
          for (final term in glossaryTerms)
            if (term.source.trim().isNotEmpty && term.target.trim().isNotEmpty)
              GlossarySyncRow(
                source: term.source.trim(),
                target: term.target.trim(),
                otherTarget: vietPhrase[term.source.trim()],
                createdBy: term.createdBy,
              ),
        ];
      }

      final glossaryBySource = {
        for (final term in glossaryTerms)
          term.source.trim().toLowerCase(): term.target,
      };
      return [
        for (final entry in vietPhrase.entries)
          if (glossaryTargetOf(entry.value).isNotEmpty)
            GlossarySyncRow(
              source: entry.key,
              target: glossaryTargetOf(entry.value),
              otherTarget: glossaryBySource[entry.key.trim().toLowerCase()],
            ),
      ];
    });

/// Lọc danh sách theo bộ lọc của màn đồng bộ. [createdByAiOnly] chỉ có nghĩa ở
/// chiều Glossary → VietPhrase; chiều ngược lại luôn truyền `false`.
List<GlossarySyncRow> filterGlossarySyncRows(
  List<GlossarySyncRow> rows, {
  required DuplicateFilter duplicateFilter,
  required bool createdByAiOnly,
  String search = '',
}) {
  final query = search.trim().toLowerCase();
  return rows.where((row) {
    if (duplicateFilter == DuplicateFilter.duplicated) {
      if (!row.isDuplicate || row.isIdentical) return false;
    } else {
      if (row.isDuplicate) return false;
    }
    if (createdByAiOnly && !row.isCreatedByAi) return false;
    if (query.isEmpty) return true;
    return row.source.toLowerCase().contains(query) ||
        row.target.toLowerCase().contains(query);
  }).toList();
}

/// Ghi [rows] sang bên đích của [direction]:
/// - Glossary → VietPhrase: lưu cục bộ + xếp hàng chờ bấm Update lên server.
/// - VietPhrase → Glossary: ghi thẳng vào `Global Glossary.json`
///   (`created_by = user`).
Future<void> applyGlossarySyncRows(
  WidgetRef ref,
  GlossarySyncDirection direction,
  List<GlossarySyncRow> rows,
) async {
  if (rows.isEmpty) return;
  final mode = ref.read(translationControllerProvider).mode;

  if (direction == GlossarySyncDirection.glossaryToVietPhrase) {
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(
          mode: mode,
          entries: [
            for (final row in rows)
              SharedDictionaryEntry(
                kind: SharedDictionaryKind.vietPhrase,
                source: row.source,
                target: row.target,
              ),
          ],
        );
  } else {
    final service = GlossaryService(ref.read(settingsProvider).glossaryDir);
    await service.upsertAll(mode, {
      for (final row in rows) row.source: row.target,
    });
  }
  ref.invalidate(glossarySyncRowsProvider(direction));
}
