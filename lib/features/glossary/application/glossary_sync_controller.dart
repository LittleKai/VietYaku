import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../clipboard/application/clipboard_reader_controller.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/lookup_controller.dart';
import '../../translation/application/trad2simp_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/trad2simp_table.dart';
import '../../translation/domain/translation_engine.dart';
import '../data/glossary_service.dart';
import '../domain/glossary_term.dart';
import '../presentation/glossary_update_dialog.dart' show glossaryTargetOf;
import 'glossary_service_provider.dart';

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

/// Tiêu chí sắp xếp danh sách ở màn đồng bộ Glossary ↔ VietPhrase.
enum GlossarySyncSortBy {
  defaultOrder('Mặc định', defaultAscending: true),
  dateAdded('Thời gian thêm', defaultAscending: false),
  source('Từ gốc', defaultAscending: true),
  target('Nghĩa tiếng Việt', defaultAscending: true),
  sourceLength('Độ dài từ gốc', defaultAscending: true);

  const GlossarySyncSortBy(this.label, {required this.defaultAscending});

  final String label;
  final bool defaultAscending;

  String directionLabel({required bool ascending}) => switch (this) {
    GlossarySyncSortBy.defaultOrder => 'Theo file',
    GlossarySyncSortBy.dateAdded => ascending ? 'Cũ → Mới' : 'Mới → Cũ',
    GlossarySyncSortBy.source ||
    GlossarySyncSortBy.target => ascending ? 'A → Z' : 'Z → A',
    GlossarySyncSortBy.sourceLength => ascending ? 'Ngắn → Dài' : 'Dài → Ngắn',
  };
}

final _isoDatePrefixRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
final _dateSplitRe = RegExp(r'[-/]');

/// Chuyển chuỗi `date_added` của glossary thành milliseconds để so sánh nhanh.
/// Trả `null` nếu rỗng hoặc không hợp lệ.
int? parseGlossaryDateMillis(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final direct = DateTime.tryParse(s);
  if (direct != null) {
    // DateTime.tryParse tự cộng tràn ngày không hợp lệ (vd 2026-02-30 → 03-02).
    final dateMatch = _isoDatePrefixRe.firstMatch(s);
    if (dateMatch != null) {
      final y = int.parse(dateMatch.group(1)!);
      final m = int.parse(dateMatch.group(2)!);
      final d = int.parse(dateMatch.group(3)!);
      final check = DateTime(y, m, d);
      if (y < 1900 || check.year != y || check.month != m || check.day != d) {
        return null;
      }
    }
    return direct.millisecondsSinceEpoch;
  }

  final parts = s.split(_dateSplitRe);
  if (parts.length != 3) return null;
  final p0 = int.tryParse(parts[0]);
  final p1 = int.tryParse(parts[1]);
  final p2 = int.tryParse(parts[2]);
  if (p0 == null || p1 == null || p2 == null) return null;

  final int year;
  final int month;
  final int day;
  if (p0 >= 1900) {
    year = p0;
    month = p1;
    day = p2;
  } else if (p2 >= 1900) {
    day = p0;
    month = p1;
    year = p2;
  } else {
    return null;
  }

  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final dt = DateTime(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return dt.millisecondsSinceEpoch;
}

const _vietnameseGroups = <String>[
  'AaÀàẢảÃãÁáẠạ',
  'ĂăẰằẲẳẴẵẮắẶặ',
  'ÂâẦầẨẩẪẫẤấẬậ',
  'Bb',
  'Cc',
  'Dd',
  'Đđ',
  'EeÈèẺẻẼẽÉéẸẹ',
  'ÊêỀềỂểỄễẾếỆệ',
  'Ff',
  'Gg',
  'Hh',
  'IiÌìỈỉĨĩÍíỊị',
  'Jj',
  'Kk',
  'Ll',
  'Mm',
  'Nn',
  'OoÒòỎỏÕõÓóỌọ',
  'ÔôỒồỔổỖỗỐốỘộ',
  'ƠơỜờỞởỠỡỚớỢợ',
  'Pp',
  'Qq',
  'Rr',
  'Ss',
  'Tt',
  'UuÙùỦủŨũÚúỤụ',
  'ƯưỪừỬửỮữỨứỰự',
  'Vv',
  'Ww',
  'Xx',
  'YyỲỳỶỷỸỹÝýỴỵ',
  'Zz',
];

({List<int> asciiPrimary, Map<int, int> primary, Map<int, int> tone})?
_vnRankTables;

({List<int> asciiPrimary, Map<int, int> primary, Map<int, int> tone})
_ensureVnRankTables() {
  final existing = _vnRankTables;
  if (existing != null) return existing;
  final asciiPrimary = List<int>.generate(128, (i) => i, growable: false);
  final primary = <int, int>{};
  final tone = <int, int>{};
  for (var groupIdx = 0; groupIdx < _vietnameseGroups.length; groupIdx++) {
    final group = _vietnameseGroups[groupIdx];
    final rank = 0x100 + groupIdx;
    for (var charIdx = 0; charIdx < group.length; charIdx++) {
      final cu = group.codeUnitAt(charIdx);
      if (cu < 0x80) {
        asciiPrimary[cu] = rank;
      } else {
        primary[cu] = rank;
        final toneRank = charIdx ~/ 2;
        if (toneRank > 0) {
          tone[cu] = toneRank;
        }
      }
    }
  }
  final built = (asciiPrimary: asciiPrimary, primary: primary, tone: tone);
  _vnRankTables = built;
  return built;
}

/// So sánh hai chuỗi theo bảng chữ cái và thanh điệu tiếng Việt, không cấp phát
/// chuỗi mới để dùng trực tiếp khi sort hàng trăm nghìn dòng.
int compareVietnameseText(String a, String b) {
  final tables = _ensureVnRankTables();
  final asciiPrimary = tables.asciiPrimary;
  final vnPrimary = tables.primary;
  final vnTone = tables.tone;

  final lenA = a.length;
  final lenB = b.length;
  final minLen = lenA < lenB ? lenA : lenB;

  for (var i = 0; i < minLen; i++) {
    final cuA = a.codeUnitAt(i);
    final cuB = b.codeUnitAt(i);
    if (cuA == cuB) continue;
    final rankA = cuA < 0x80
        ? asciiPrimary[cuA]
        : (vnPrimary[cuA] ?? (0x200 + cuA));
    final rankB = cuB < 0x80
        ? asciiPrimary[cuB]
        : (vnPrimary[cuB] ?? (0x200 + cuB));
    if (rankA != rankB) return rankA.compareTo(rankB);
  }
  if (lenA != lenB) return lenA.compareTo(lenB);

  for (var i = 0; i < minLen; i++) {
    final cuA = a.codeUnitAt(i);
    final cuB = b.codeUnitAt(i);
    if (cuA == cuB) continue;
    final toneA = cuA < 0x80 ? 0 : (vnTone[cuA] ?? 0);
    final toneB = cuB < 0x80 ? 0 : (vnTone[cuB] ?? 0);
    if (toneA != toneB) return toneA.compareTo(toneB);
  }

  return a.compareTo(b);
}

bool _isAiCreatedBy(String createdBy) {
  if (createdBy.isEmpty) return false;
  final norm = _fastNormKey(createdBy);
  return norm == 'a.i' || norm == 'ai';
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

  /// Ngày thêm trong glossary (`date_added`, thường dạng `YYYY-MM-DD`).
  final String dateAdded;

  /// Mốc thời gian thêm tính sẵn bằng milliseconds để sort nhanh.
  final int? dateAddedMillis;

  /// Đã có bên đích và nghĩa chính y hệt — tính sẵn một lần để lọc hàng trăm
  /// nghìn dòng không phải parse lại VietPhrase.
  final bool isIdentical;

  /// Do A.I sinh ra (glossary dùng "A.I"; chấp nhận cả biến thể "ai").
  final bool isCreatedByAi;

  GlossarySyncRow({
    required this.source,
    required this.target,
    required this.otherTarget,
    this.createdBy = '',
    this.dateAdded = '',
    bool? isIdentical,
  }) : isIdentical =
           isIdentical ??
           (otherTarget != null &&
               glossaryTargetOf(otherTarget) == glossaryTargetOf(target)),
       isCreatedByAi = _isAiCreatedBy(createdBy),
       dateAddedMillis = parseGlossaryDateMillis(dateAdded);

  bool get isDuplicate => otherTarget != null;
}

bool _isWhitespaceUnit(int cu) =>
    cu <= 0x20 ||
    cu == 0x85 ||
    cu == 0xA0 ||
    (cu >= 0x1680 &&
        (cu == 0x1680 ||
            (cu >= 0x2000 && cu <= 0x200A) ||
            cu == 0x2028 ||
            cu == 0x2029 ||
            cu == 0x202F ||
            cu == 0x205F ||
            cu == 0x3000 ||
            cu == 0xFEFF));

/// Kiểm tra nhanh chuỗi đã được trim và không chứa ký tự chữ hoa cần hạ
/// (99.99% key CJK trong VietPhrase thoả điều kiện này → 0 cấp phát chuỗi).
bool _isAlreadyNormalizedKey(String s) {
  final len = s.length;
  if (len == 0) return true;
  if (_isWhitespaceUnit(s.codeUnitAt(0)) ||
      _isWhitespaceUnit(s.codeUnitAt(len - 1))) {
    return false;
  }
  for (var i = 0; i < len; i++) {
    final cu = s.codeUnitAt(i);
    // CJK Unified Ideographs + Hiragana/Katakana không có chữ hoa/thường.
    if (cu >= 0x3040 && cu <= 0x9FFF) continue;
    // ASCII uppercase A-Z
    if (cu >= 0x41 && cu <= 0x5A) return false;
    // Latin mở rộng / Fullwidth A-Z / Greek / Cyrillic / Roman numerals
    if ((cu >= 0x00C0 && cu <= 0x02AF) ||
        (cu >= 0x0370 && cu <= 0x04FF) ||
        (cu >= 0x1E00 && cu <= 0x1EFF) ||
        (cu >= 0x2160 && cu <= 0x217F) ||
        (cu >= 0xFF21 && cu <= 0xFF3A)) {
      return false;
    }
  }
  return true;
}

String _fastNormKey(String s) =>
    _isAlreadyNormalizedKey(s) ? s : s.trim().toLowerCase();

/// Chỉ mục VietPhrase giữ trong RAM theo từng ngôn ngữ để:
/// 1. Tab `Glossary → VietPhrase` tra trực tiếp O(1) mà không phải dựng lại map
///    691k mục mỗi lần.
/// 2. Tab `VietPhrase → Glossary` chỉ dựng danh sách `GlossarySyncRow` nền đúng
///    một lần và tái sử dụng 99% phần tử khi chỉ vài mục đổi.
/// 3. Các thao tác Cập nhật / Sửa / Xóa vá thẳng vào chỉ mục trong <1ms thay vì
///    chờ nạp lại toàn bộ từ điển rồi quét lại 691k mục.
class _VietPhraseSyncIndex {
  Map<String, String> sourceEntries;
  final String trad2simpSignature;

  /// Chỉ giữ những key trong [sourceEntries] có chữ hoa hoặc khoảng trắng đầu/cuối.
  final Map<String, String> fallbackRawByNormKey = <String, String>{};

  /// Các mục vừa thêm/sửa trực tiếp trên màn đồng bộ trước khi `sourceEntries`
  /// được nạp lại.
  final Map<String, ({String rawKey, String rawValue})> localUpserts =
      <String, ({String rawKey, String rawValue})>{};
  final Set<String> localDeletedNormKeys = <String>{};

  List<GlossarySyncRow>? _baseRows;
  Map<String, int>? _indexByNormKey;

  _VietPhraseSyncIndex({
    required this.sourceEntries,
    required this.trad2simpSignature,
  }) {
    for (final entry in sourceEntries.entries) {
      final key = entry.key;
      if (!_isAlreadyNormalizedKey(key)) {
        final norm = key.trim().toLowerCase();
        if (norm.isNotEmpty) {
          fallbackRawByNormKey.putIfAbsent(norm, () => entry.value);
        }
      }
    }
  }

  String? lookupRawValue(String normKey) {
    if (normKey.isEmpty || localDeletedNormKeys.contains(normKey)) return null;
    final local = localUpserts[normKey];
    if (local != null) return local.rawValue;
    return sourceEntries[normKey] ?? fallbackRawByNormKey[normKey];
  }

  void ensureBaseRowsBuilt() {
    if (_baseRows != null && _indexByNormKey != null) return;
    final rows = <GlossarySyncRow>[];
    final indexMap = <String, int>{};

    for (final entry in sourceEntries.entries) {
      final rawKey = entry.key;
      final normKey = _fastNormKey(rawKey);
      if (normKey.isEmpty ||
          localDeletedNormKeys.contains(normKey) ||
          indexMap.containsKey(normKey)) {
        continue;
      }
      final override = localUpserts[normKey];
      final effectiveKey = override != null ? override.rawKey : rawKey;
      final effectiveVal = override != null ? override.rawValue : entry.value;
      final cleanTarget = glossaryTargetOf(effectiveVal);
      if (cleanTarget.isEmpty) continue;
      indexMap[normKey] = rows.length;
      rows.add(
        GlossarySyncRow(
          source: effectiveKey,
          target: cleanTarget,
          otherTarget: null,
          isIdentical: false,
        ),
      );
    }

    for (final entry in localUpserts.entries) {
      final normKey = entry.key;
      if (localDeletedNormKeys.contains(normKey) ||
          indexMap.containsKey(normKey)) {
        continue;
      }
      final cleanTarget = glossaryTargetOf(entry.value.rawValue);
      if (cleanTarget.isEmpty) continue;
      indexMap[normKey] = rows.length;
      rows.add(
        GlossarySyncRow(
          source: entry.value.rawKey,
          target: cleanTarget,
          otherTarget: null,
          isIdentical: false,
        ),
      );
    }

    _baseRows = rows;
    _indexByNormKey = indexMap;
  }

  List<GlossarySyncRow> buildVietPhraseToGlossaryRows(
    Map<String, GlossaryTerm> glossaryByNormKey,
  ) {
    ensureBaseRowsBuilt();
    final rows = List<GlossarySyncRow>.of(_baseRows!);
    final indexMap = _indexByNormKey!;
    for (final gEntry in glossaryByNormKey.entries) {
      final idx = indexMap[gEntry.key];
      if (idx != null) {
        final base = rows[idx];
        final term = gEntry.value;
        rows[idx] = GlossarySyncRow(
          source: term.source.trim(),
          target: base.target,
          otherTarget: term.target.trim(),
          dateAdded: term.dateAdded,
        );
      }
    }
    return rows;
  }

  void applyUpserts(Map<String, String> rawValueBySource) {
    if (rawValueBySource.isEmpty) return;
    final rows = _baseRows;
    final indexMap = _indexByNormKey;

    for (final entry in rawValueBySource.entries) {
      final rawKey = entry.key.trim();
      final rawVal = entry.value.trim();
      final normKey = _fastNormKey(rawKey);
      if (normKey.isEmpty) continue;
      localDeletedNormKeys.remove(normKey);
      localUpserts[normKey] = (rawKey: rawKey, rawValue: rawVal);

      if (rows != null && indexMap != null) {
        final cleanTarget = glossaryTargetOf(rawVal);
        final existingIdx = indexMap[normKey];
        if (cleanTarget.isEmpty) {
          if (existingIdx != null) {
            _removeRowAt(rows, indexMap, existingIdx, normKey);
          }
          continue;
        }
        final newRow = GlossarySyncRow(
          source: rawKey,
          target: cleanTarget,
          otherTarget: null,
          isIdentical: false,
        );
        if (existingIdx != null) {
          rows[existingIdx] = newRow;
        } else {
          indexMap[normKey] = rows.length;
          rows.add(newRow);
        }
      }
    }
  }

  void applyDeletes(Iterable<String> keys) {
    final normKeysToRemove = <String>{};
    for (final key in keys) {
      final norm = _fastNormKey(key);
      if (norm.isNotEmpty) {
        normKeysToRemove.add(norm);
        localUpserts.remove(norm);
        localDeletedNormKeys.add(norm);
      }
    }
    if (normKeysToRemove.isEmpty) return;

    final rows = _baseRows;
    final indexMap = _indexByNormKey;
    if (rows != null && indexMap != null) {
      final existingKeys = [
        for (final k in normKeysToRemove)
          if (indexMap.containsKey(k)) k,
      ];
      if (existingKeys.isEmpty) return;
      if (existingKeys.length == 1) {
        final single = existingKeys.first;
        final idx = indexMap[single];
        if (idx != null) {
          _removeRowAt(rows, indexMap, idx, single);
        }
      } else {
        final removeSet = existingKeys.toSet();
        final nextRows = <GlossarySyncRow>[];
        final nextIndex = <String, int>{};
        for (final row in rows) {
          final norm = _fastNormKey(row.source);
          if (removeSet.contains(norm)) continue;
          nextIndex[norm] = nextRows.length;
          nextRows.add(row);
        }
        _baseRows = nextRows;
        _indexByNormKey = nextIndex;
      }
    }
  }

  static void _removeRowAt(
    List<GlossarySyncRow> rows,
    Map<String, int> indexMap,
    int idx,
    String normKey,
  ) {
    indexMap.remove(normKey);
    rows.removeAt(idx);
    for (var i = idx; i < rows.length; i++) {
      indexMap[_fastNormKey(rows[i].source)] = i;
    }
  }
}

final Map<TranslationMode, _VietPhraseSyncIndex> _syncIndexByMode = {};

/// Xóa cache chỉ mục VietPhrase của màn đồng bộ (dùng khi cửa sổ bên kia báo có
/// thay đổi hoặc khi nạp lại từ điển từ bên ngoài).
void invalidateVietPhraseSyncIndex([TranslationMode? mode]) {
  if (mode == null) {
    _syncIndexByMode.clear();
  } else {
    _syncIndexByMode.remove(mode);
  }
}

/// Nạp lại dữ liệu Glossary và VietPhrase từ đĩa cho màn hình đồng bộ.
Future<void> refreshGlossarySyncData(WidgetRef ref) async {
  GlossaryService.clearCache();
  invalidateVietPhraseSyncIndex();
  await ref.read(dictionariesProvider.notifier).reload();
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
}

/// Báo cho bảng đồng bộ (trong cùng cửa sổ và cửa sổ tách rời nếu đang mở)
/// biết dữ liệu Glossary đã thay đổi từ hộp thoại bên ngoài.
void notifyGlossaryChanged(WidgetRef ref, TranslationMode mode) {
  try {
    ref.invalidate(
      glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
    );
    ref.invalidate(
      glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
    );
    unawaited(
      ref.read(windowsClipboardBridgeProvider).notifyGlossaryWindow({
        'type': 'glossaryChanged',
        'mode': mode.name,
        'glossaryChanged': true,
      }),
    );
  } catch (_) {
    // Widget gọi dialog có thể đã unmount trong lúc thao tác async chạy.
  }
}

_VietPhraseSyncIndex _getOrCreateSyncIndex(
  TranslationMode mode,
  Map<String, String> vietPhraseEntries,
  String trad2simpSignature,
) {
  final existing = _syncIndexByMode[mode];
  if (existing != null &&
      existing.trad2simpSignature == trad2simpSignature &&
      identical(existing.sourceEntries, vietPhraseEntries)) {
    return existing;
  }
  final created = _VietPhraseSyncIndex(
    sourceEntries: vietPhraseEntries,
    trad2simpSignature: trad2simpSignature,
  );
  _syncIndexByMode[mode] = created;
  return created;
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
      final rawGlossaryFuture = service.readAll(mode);
      final dicts = await ref.watch(dictionariesProvider.future);
      final trad2simp = await trad2simpFuture ?? Trad2SimpTable.empty;
      final rawGlossaryTerms = await rawGlossaryFuture;

      final syncIndex = _getOrCreateSyncIndex(
        mode,
        dicts.vietPhrase.entries,
        trad2simp.signature,
      );

      final glossaryTerms = <GlossaryTerm>[];
      final glossaryByNormKey = <String, GlossaryTerm>{};

      for (final term in rawGlossaryTerms) {
        final source = term.source.trim();
        final target = term.target.trim();
        if (source.isEmpty || target.isEmpty) continue;
        final normKey = _fastNormKey(trad2simp.convert(source));
        if (!glossaryByNormKey.containsKey(normKey)) {
          glossaryByNormKey[normKey] = term;
          glossaryTerms.add(term);
        }
      }

      if (direction == GlossarySyncDirection.glossaryToVietPhrase) {
        return [
          for (final term in glossaryTerms)
            GlossarySyncRow(
              source: term.source.trim(),
              target: term.target.trim(),
              otherTarget: syncIndex.lookupRawValue(
                _fastNormKey(trad2simp.convert(term.source.trim())),
              ),
              createdBy: term.createdBy,
              dateAdded: term.dateAdded,
            ),
        ];
      }

      return syncIndex.buildVietPhraseToGlossaryRows(glossaryByNormKey);
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
  if (duplicateFilter == DuplicateFilter.all &&
      !createdByAiOnly &&
      query.isEmpty) {
    return rows;
  }
  final hasQuery = query.isNotEmpty;
  final result = <GlossarySyncRow>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    switch (duplicateFilter) {
      case DuplicateFilter.notDuplicated:
        if (row.isDuplicate) continue;
      case DuplicateFilter.duplicated:
        if (!row.isDuplicate || row.isIdentical) continue;
      case DuplicateFilter.identical:
        if (!row.isDuplicate || !row.isIdentical) continue;
      case DuplicateFilter.all:
        break;
    }
    if (createdByAiOnly && !row.isCreatedByAi) continue;
    if (hasQuery &&
        !_fastNormKey(row.source).contains(query) &&
        !row.target.toLowerCase().contains(query)) {
      continue;
    }
    result.add(row);
  }
  return result;
}

/// Sắp xếp danh sách đã lọc theo [sortBy] và chiều [ascending]. Giữ tính ổn
/// định (stable) theo thứ tự gốc khi hai mục bằng nhau.
List<GlossarySyncRow> sortGlossarySyncRows(
  List<GlossarySyncRow> rows, {
  required GlossarySyncSortBy sortBy,
  required bool ascending,
}) {
  if (sortBy == GlossarySyncSortBy.defaultOrder || rows.length <= 1) {
    return rows;
  }

  final indices = List<int>.generate(rows.length, (i) => i, growable: false);
  final dir = ascending ? 1 : -1;

  switch (sortBy) {
    case GlossarySyncSortBy.defaultOrder:
      return rows;
    case GlossarySyncSortBy.dateAdded:
      indices.sort((ia, ib) {
        final da = rows[ia].dateAddedMillis;
        final db = rows[ib].dateAddedMillis;
        if (da != null && db != null) {
          final cmp = da.compareTo(db);
          if (cmp != 0) return cmp * dir;
          // File glossary nối mục mới vào cuối nên cùng ngày mục sau mới hơn.
          return ia.compareTo(ib) * dir;
        }
        if (da != null) return -1;
        if (db != null) return 1;
        return ia.compareTo(ib) * dir;
      });
    case GlossarySyncSortBy.source:
      indices.sort((ia, ib) {
        final cmp = compareVietnameseText(rows[ia].source, rows[ib].source);
        if (cmp != 0) return cmp * dir;
        return ia.compareTo(ib);
      });
    case GlossarySyncSortBy.target:
      indices.sort((ia, ib) {
        final cmp = compareVietnameseText(rows[ia].target, rows[ib].target);
        if (cmp != 0) return cmp * dir;
        return ia.compareTo(ib);
      });
    case GlossarySyncSortBy.sourceLength:
      final lengths = List<int>.generate(
        rows.length,
        (i) => rows[i].source.runes.length,
        growable: false,
      );
      indices.sort((ia, ib) {
        final lenCmp = lengths[ia].compareTo(lengths[ib]);
        if (lenCmp != 0) return lenCmp * dir;
        final textCmp = compareVietnameseText(rows[ia].source, rows[ib].source);
        if (textCmp != 0) return textCmp;
        return ia.compareTo(ib);
      });
  }

  return [for (final i in indices) rows[i]];
}

bool _pendingMainTranslationReload = false;

/// Khi màn đồng bộ mở dạng route nội bộ (fallback) và có sửa VietPhrase, chỉ
/// nạp lại từ điển + dịch lại một lần lúc đóng màn thay vì sau mỗi lần bấm.
void flushPendingGlossarySyncReload(WidgetRef ref) {
  if (!_pendingMainTranslationReload) return;
  _pendingMainTranslationReload = false;
  unawaited(
    ref.read(dictionarySyncProvider.notifier).reloadCurrentTranslation(),
  );
}

void _afterSyncMutation(
  WidgetRef ref, {
  required TranslationMode mode,
  required bool vietPhraseChanged,
  required bool glossaryChanged,
}) {
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );

  final isStandaloneSyncWindow = ref.read(vietPhraseOnlyModeProvider);
  final bridge = ref.read(windowsClipboardBridgeProvider);
  if (isStandaloneSyncWindow) {
    unawaited(
      bridge.notifyMainWindow({
        'type': 'glossarySyncUpdated',
        'mode': mode.name,
        'vietPhraseChanged': vietPhraseChanged,
        'glossaryChanged': glossaryChanged,
      }),
    );
  } else {
    if (vietPhraseChanged) {
      _pendingMainTranslationReload = true;
    }
    unawaited(
      bridge.notifyGlossaryWindow({
        'type': 'mainDataUpdated',
        'mode': mode.name,
        'vietPhraseChanged': vietPhraseChanged,
        'glossaryChanged': glossaryChanged,
      }),
    );
  }
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
    final upserts = <String, String>{};
    final entries = <SharedDictionaryEntry>[];
    for (final row in rows) {
      final key = lookupKeyOf(ref, row.source);
      upserts[key] = row.target;
      entries.add(
        SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: key,
          target: row.target,
        ),
      );
    }
    _syncIndexByMode[mode]?.applyUpserts(upserts);
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(
          mode: mode,
          entries: entries,
          reloadDictionaries: false,
        );
    _afterSyncMutation(
      ref,
      mode: mode,
      vietPhraseChanged: true,
      glossaryChanged: false,
    );
  } else {
    final service = ref.read(glossaryServiceProvider);
    await service.upsertAll(mode, {
      for (final row in rows) row.source: row.target,
    });
    _afterSyncMutation(
      ref,
      mode: mode,
      vietPhraseChanged: false,
      glossaryChanged: true,
    );
  }
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
    final service = ref.read(glossaryServiceProvider);
    await service.removeAll(mode, rows.map((r) => r.source));
  }

  if (deleteFromVietPhrase) {
    final entries = <SharedDictionaryEntry>[];
    final deletedKeys = <String>[];
    for (final row in rows) {
      final norm = lookupKeyOf(ref, row.source);
      deletedKeys.add(norm);
      entries.add(
        SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: norm,
          operation: EntryOperation.delete,
        ),
      );
      if (norm != row.source) {
        deletedKeys.add(row.source);
        entries.add(
          SharedDictionaryEntry(
            kind: SharedDictionaryKind.vietPhrase,
            source: row.source,
            operation: EntryOperation.delete,
          ),
        );
      }
    }
    _syncIndexByMode[mode]?.applyDeletes(deletedKeys);
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(
          mode: mode,
          entries: entries,
          reloadDictionaries: false,
        );
  }

  _afterSyncMutation(
    ref,
    mode: mode,
    vietPhraseChanged: deleteFromVietPhrase,
    glossaryChanged: deleteFromGlossary,
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
  if (source.isEmpty ||
      target.isEmpty ||
      (!updateGlossary && !updateVietPhrase)) {
    return;
  }
  final mode = ref.read(translationControllerProvider).mode;
  final oldSource = oldRow.source.trim();
  final sourceChanged = source != oldSource;

  if (updateGlossary) {
    final service = ref.read(glossaryServiceProvider);
    if (sourceChanged) {
      await service.removeAll(mode, [oldSource]);
    }
    await service.upsertAll(mode, {source: target});
  }

  if (updateVietPhrase) {
    final entries = <SharedDictionaryEntry>[];
    final index = _syncIndexByMode[mode];
    if (sourceChanged) {
      final oldNorm = lookupKeyOf(ref, oldSource);
      index?.applyDeletes([oldNorm, if (oldNorm != oldSource) oldSource]);
      entries.add(
        SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: oldNorm,
          operation: EntryOperation.delete,
        ),
      );
      if (oldNorm != oldSource) {
        entries.add(
          SharedDictionaryEntry(
            kind: SharedDictionaryKind.vietPhrase,
            source: oldSource,
            operation: EntryOperation.delete,
          ),
        );
      }
    }
    final newKey = lookupKeyOf(ref, source);
    index?.applyUpserts({newKey: target});
    entries.add(
      SharedDictionaryEntry(
        kind: SharedDictionaryKind.vietPhrase,
        source: newKey,
        target: target,
      ),
    );
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(
          mode: mode,
          entries: entries,
          reloadDictionaries: false,
        );
  }

  _afterSyncMutation(
    ref,
    mode: mode,
    vietPhraseChanged: updateVietPhrase,
    glossaryChanged: updateGlossary,
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
    final service = ref.read(glossaryServiceProvider);
    await service.upsertAll(mode, updatedPairs);
  }

  if (updateVietPhrase) {
    final vpUpserts = <String, String>{};
    final entries = <SharedDictionaryEntry>[];
    for (final entry in updatedPairs.entries) {
      final key = lookupKeyOf(ref, entry.key);
      vpUpserts[key] = entry.value;
      entries.add(
        SharedDictionaryEntry(
          kind: SharedDictionaryKind.vietPhrase,
          source: key,
          target: entry.value,
        ),
      );
    }
    _syncIndexByMode[mode]?.applyUpserts(vpUpserts);
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEditsBulk(
          mode: mode,
          entries: entries,
          reloadDictionaries: false,
        );
  }

  _afterSyncMutation(
    ref,
    mode: mode,
    vietPhraseChanged: updateVietPhrase,
    glossaryChanged: updateGlossary,
  );
}
