import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/trad2simp_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/trad2simp_table.dart';
import '../../translation/domain/translation_engine.dart';
import '../data/glossary_service.dart';
import '../domain/glossary_term.dart';
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
  duplicated('Khác nghĩa'),
  identical('Giống hệt'),
  all('Tất cả');

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

  /// Đã có bên đích và nghĩa chính y hệt — áp dụng cũng không đổi gì.
  bool get isIdentical {
    final other = otherTarget;
    if (other == null) return false;
    return glossaryTargetOf(other) == glossaryTargetOf(target);
  }

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
      // Mode Trung quy key dict về giản thể lúc nạp, nên source phồn thể của
      // glossary phải quy trước khi tra — không thì mục đã có vẫn báo "không
      // trùng" và bấm Cập nhật bao nhiêu lần cũng không biến mất.
      final trad2simpFuture =
          mode == TranslationMode.chinese &&
              ref.watch(
                settingsProvider.select(
                  (s) => s.convertTraditionalToSimplified,
                ),
              )
          ? ref.watch(trad2SimpTableProvider.future)
          : null;
      final dicts = await ref.watch(dictionariesProvider.future);
      final trad2simp = await trad2simpFuture ?? Trad2SimpTable.empty;
      final rawGlossaryTerms = await service.readAll(mode);

      final vietPhraseBySource = <String, String>{};
      for (final entry in dicts.vietPhrase.entries.entries) {
        final key = entry.key.trim().toLowerCase();
        if (key.isNotEmpty) {
          vietPhraseBySource.putIfAbsent(key, () => entry.value);
        }
      }

      final glossaryTerms = <GlossaryTerm>[];
      final glossaryBySource = <String, String>{};
      final seenGlossaryKeys = <String>{};

      for (final term in rawGlossaryTerms) {
        final source = term.source.trim();
        final target = term.target.trim();
        if (source.isEmpty || target.isEmpty) continue;
        final normKey = trad2simp.convert(source).toLowerCase();
        if (seenGlossaryKeys.add(normKey)) {
          glossaryTerms.add(term);
          glossaryBySource[normKey] = target;
        }
      }

      if (direction == GlossarySyncDirection.glossaryToVietPhrase) {
        return [
          for (final term in glossaryTerms)
            GlossarySyncRow(
              source: term.source.trim(),
              target: term.target.trim(),
              otherTarget: vietPhraseBySource[
                  trad2simp.convert(term.source.trim()).toLowerCase()],
              createdBy: term.createdBy,
            ),
        ];
      }

      return [
        for (final entry in dicts.vietPhrase.entries.entries)
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
    switch (duplicateFilter) {
      case DuplicateFilter.notDuplicated:
        if (row.isDuplicate) return false;
        break;
      case DuplicateFilter.duplicated:
        if (!row.isDuplicate || row.isIdentical) return false;
        break;
      case DuplicateFilter.identical:
        if (!row.isDuplicate || !row.isIdentical) return false;
        break;
      case DuplicateFilter.all:
        break;
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
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
}

/// Xóa các mục [rows] khỏi các bên được chọn (Glossary và/hoặc VietPhrase).
Future<void> deleteGlossarySyncRows(
  WidgetRef ref, {
  required List<GlossarySyncRow> rows,
  required bool deleteFromGlossary,
  required bool deleteFromVietPhrase,
}) async {
  if (rows.isEmpty || (!deleteFromGlossary && !deleteFromVietPhrase)) return;
  final mode = ref.read(translationControllerProvider).mode;

  if (deleteFromGlossary) {
    final service = GlossaryService(ref.read(settingsProvider).glossaryDir);
    await service.removeAll(mode, rows.map((r) => r.source));
  }

  if (deleteFromVietPhrase) {
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(
          mode: mode,
          entries: [
            for (final row in rows)
              SharedDictionaryEntry(
                kind: SharedDictionaryKind.vietPhrase,
                source: row.source,
                operation: EntryOperation.delete,
              ),
          ],
        );
  }

  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
}

/// Sửa 1 mục [oldRow] thành [newSource] và [newTarget] ở các bên được chọn.
/// Nếu từ nguồn bị đổi, xóa mục từ nguồn cũ ở các bên tương ứng trước.
Future<void> editGlossarySyncRow(
  WidgetRef ref, {
  required GlossarySyncRow oldRow,
  required String newSource,
  required String newTarget,
  required bool updateGlossary,
  required bool updateVietPhrase,
}) async {
  final source = newSource.trim();
  final target = newTarget.trim();
  if (source.isEmpty || target.isEmpty || (!updateGlossary && !updateVietPhrase)) {
    return;
  }
  final mode = ref.read(translationControllerProvider).mode;
  final oldSource = oldRow.source.trim();
  final sourceChanged = source != oldSource;

  if (updateGlossary) {
    final service = GlossaryService(ref.read(settingsProvider).glossaryDir);
    if (sourceChanged) {
      await service.removeAll(mode, [oldSource]);
    }
    await service.upsert(mode, source: source, target: target);
  }

  if (updateVietPhrase) {
    final entries = <SharedDictionaryEntry>[];
    if (sourceChanged) {
      entries.add(
        SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: oldSource,
          operation: EntryOperation.delete,
        ),
      );
    }
    entries.add(
      SharedDictionaryEntry(
        kind: SharedDictionaryKind.vietPhrase,
        source: source,
        target: target,
      ),
    );
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(mode: mode, entries: entries);
  }

  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
}

/// Sửa hàng loạt [rows] bằng nghĩa mới [newTarget] (hoặc thay thế [findText] → [replaceText]).
Future<void> bulkEditGlossarySyncRows(
  WidgetRef ref, {
  required List<GlossarySyncRow> rows,
  required String newTarget,
  required bool isReplaceMode,
  required String findText,
  required String replaceText,
  required bool updateGlossary,
  required bool updateVietPhrase,
}) async {
  if (rows.isEmpty || (!updateGlossary && !updateVietPhrase)) return;
  final mode = ref.read(translationControllerProvider).mode;

  final updatedPairs = <String, String>{};
  for (final row in rows) {
    final target = isReplaceMode
        ? row.target.replaceAll(findText, replaceText).trim()
        : newTarget.trim();
    if (target.isNotEmpty) {
      updatedPairs[row.source] = target;
    }
  }
  if (updatedPairs.isEmpty) return;

  if (updateGlossary) {
    final service = GlossaryService(ref.read(settingsProvider).glossaryDir);
    await service.upsertAll(mode, updatedPairs);
  }

  if (updateVietPhrase) {
    final entries = [
      for (final entry in updatedPairs.entries)
        SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: entry.key,
          target: entry.value,
        ),
    ];
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(mode: mode, entries: entries);
  }

  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
}
