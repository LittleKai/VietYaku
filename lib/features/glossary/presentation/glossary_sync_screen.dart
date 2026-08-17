import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/translation_engine.dart';
import '../application/glossary_sync_controller.dart';
import '../data/glossary_service.dart';

const _glossaryAccent = Color(0xFF6A1B9A);
const _pageSizes = [25, 50, 100, 200];

/// Màn đồng bộ hàng loạt giữa Global Glossary (AI_Translation_Bridge) và
/// VietPhrase, hai chiều trên hai tab. Chỉ mở được khi đã đăng nhập quản trị.
class GlossarySyncScreen extends ConsumerWidget {
  const GlossarySyncScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const GlossarySyncScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      translationControllerProvider.select((state) => state.mode),
    );
    final lang = GlossaryService.langFor(mode);

    return DefaultTabController(
      length: GlossarySyncDirection.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Đồng bộ Glossary ↔ VietPhrase ($lang)'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SegmentedButton<TranslationMode>(
                segments: const [
                  ButtonSegment(
                    value: TranslationMode.japanese,
                    label: Text('Tiếng Nhật (JP)'),
                  ),
                  ButtonSegment(
                    value: TranslationMode.chinese,
                    label: Text('Tiếng Trung (CN)'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (value) {
                  ref
                      .read(translationControllerProvider.notifier)
                      .setMode(value.first);
                },
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final direction in GlossarySyncDirection.values)
                Tab(text: direction.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final direction in GlossarySyncDirection.values)
              _DirectionTab(direction: direction),
          ],
        ),
      ),
    );
  }
}

class _DirectionTab extends ConsumerStatefulWidget {
  const _DirectionTab({required this.direction});

  final GlossarySyncDirection direction;

  @override
  ConsumerState<_DirectionTab> createState() => _DirectionTabState();
}

class _DirectionTabState extends ConsumerState<_DirectionTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();

  bool _createdByAiOnly = true;
  DuplicateFilter _duplicateFilter = DuplicateFilter.notDuplicated;
  String _search = '';
  int _pageSize = 50;
  int _page = 0;
  bool _applying = false;

  /// Giữ cả row để áp dụng được cả những mục đã bị lọc/lật trang ra khỏi màn.
  final _selected = <String, GlossarySyncRow>{};

  /// Chỉ chiều Glossary → VietPhrase mới có `created_by` để lọc.
  bool get _hasCreatedByFilter =>
      widget.direction == GlossarySyncDirection.glossaryToVietPhrase;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Nhớ kết quả lọc gần nhất: chiều VietPhrase → Glossary có hơn 180k mục, lọc
  // lại mỗi lần tick checkbox sẽ giật.
  List<GlossarySyncRow>? _cachedSource;
  List<GlossarySyncRow>? _cachedResult;
  DuplicateFilter? _cachedDuplicateFilter;
  bool? _cachedCreatedByAiOnly;
  String? _cachedSearch;

  List<GlossarySyncRow> _filter(List<GlossarySyncRow> rows) {
    final createdByAiOnly = _hasCreatedByFilter && _createdByAiOnly;
    final cached = _cachedResult;
    if (cached != null &&
        identical(rows, _cachedSource) &&
        _cachedDuplicateFilter == _duplicateFilter &&
        _cachedCreatedByAiOnly == createdByAiOnly &&
        _cachedSearch == _search) {
      return cached;
    }
    final result = filterGlossarySyncRows(
      rows,
      duplicateFilter: _duplicateFilter,
      createdByAiOnly: createdByAiOnly,
      search: _search,
    );
    _cachedSource = rows;
    _cachedResult = result;
    _cachedDuplicateFilter = _duplicateFilter;
    _cachedCreatedByAiOnly = createdByAiOnly;
    _cachedSearch = _search;
    return result;
  }

  void _resetPaging() => setState(() => _page = 0);

  List<GlossarySyncRow> _getReverseRows(Iterable<GlossarySyncRow> rows) {
    return [
      for (final row in rows)
        if (row.otherTarget != null && row.otherTarget!.trim().isNotEmpty)
          GlossarySyncRow(
            source: row.source,
            target: row.otherTarget!.trim(),
            otherTarget: row.target,
            createdBy:
                widget.direction == GlossarySyncDirection.vietPhraseToGlossary
                    ? row.createdBy
                    : 'user',
          ),
    ];
  }

  Future<void> _apply(
    List<GlossarySyncRow> rows, {
    required bool bulk,
    GlossarySyncDirection? customDirection,
  }) async {
    if (rows.isEmpty || _applying) return;
    final direction = customDirection ?? widget.direction;
    if (bulk && !await _confirmBulk(rows.length, direction: direction)) return;
    if (!mounted) return;

    setState(() => _applying = true);
    try {
      await applyGlossarySyncRows(ref, direction, rows);
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          _selected.remove(row.source);
        }
        _cachedSource = null;
        _cachedResult = null;
        _page = 0;
      });
      _showMessage(
        rows.length == 1
            ? 'Đã cập nhật (${direction.label}): ${rows.first.source} → ${rows.first.target}'
            : 'Đã cập nhật ${rows.length} mục (${direction.label}).',
      );
    } catch (_) {
      _showMessage('Không ghi được thay đổi. Kiểm tra lại thư mục Glossary.');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _confirmDelete(List<GlossarySyncRow> rows) async {
    if (rows.isEmpty || _applying) return;
    final mode = ref.read(translationControllerProvider).mode;
    final lang = GlossaryService.langFor(mode);

    final canDeleteNotifier = ValueNotifier<bool>(true);
    _ConfirmDeleteResult? resultData;

    final confirmed = await showAppDialog<bool>(
      context: context,
      icon: Icons.delete_forever_outlined,
      accentColor: Theme.of(context).colorScheme.error,
      title: rows.length == 1 ? 'Xóa mục từ' : 'Xóa ${rows.length} mục đã chọn',
      description: rows.length == 1
          ? 'Xóa "${rows.first.source}" khỏi các bên từ điển được chọn:'
          : 'Xóa ${rows.length} mục từ đã chọn khỏi các bên từ điển:',
      width: 520,
      content: _ConfirmDeleteDialogContent(
        lang: lang,
        canDeleteNotifier: canDeleteNotifier,
        onChanged: (res) => resultData = res,
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: canDeleteNotifier,
          builder: (context, canDelete, _) => FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: canDelete ? () => Navigator.pop(dialogContext, true) : null,
            label: Text('Xóa ${rows.length} mục'),
          ),
        ),
      ],
    );
    canDeleteNotifier.disposeAfterRouteAnimation();

    if (confirmed != true || resultData == null) return;
    setState(() => _applying = true);
    try {
      await deleteGlossarySyncRows(
        ref,
        rows: rows,
        deleteFromGlossary: resultData!.deleteFromGlossary,
        deleteFromVietPhrase: resultData!.deleteFromVietPhrase,
      );
      if (!mounted) return;
      setState(() {
        for (final r in rows) {
          _selected.remove(r.source);
        }
        _cachedSource = null;
        _cachedResult = null;
      });
      _showMessage('Đã xóa ${rows.length} mục.');
    } catch (_) {
      _showMessage('Có lỗi xảy ra khi xóa.');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _showSingleEditDialog(GlossarySyncRow row) async {
    if (_applying) return;
    final mode = ref.read(translationControllerProvider).mode;
    final lang = GlossaryService.langFor(mode);

    final canSaveNotifier = ValueNotifier<bool>(true);
    _SingleEditResult? resultData;

    final saved = await showAppDialog<bool>(
      context: context,
      icon: Icons.edit_note,
      accentColor: const Color(0xFF00897B),
      title: 'Sửa mục từ',
      description: 'Chỉnh sửa từ nguồn và nghĩa tiếng Việt:',
      width: 550,
      content: _SingleEditDialogContent(
        row: row,
        lang: lang,
        canSaveNotifier: canSaveNotifier,
        onChanged: (res) => resultData = res,
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: canSaveNotifier,
          builder: (context, canSave, _) => FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 18),
            onPressed: canSave ? () => Navigator.pop(dialogContext, true) : null,
            label: const Text('Lưu thay đổi'),
          ),
        ),
      ],
    );
    canSaveNotifier.disposeAfterRouteAnimation();

    if (saved != true || resultData == null) return;
    final newSource = resultData!.newSource.trim();
    final newTarget = resultData!.newTarget.trim();
    if (newSource.isEmpty || newTarget.isEmpty) return;

    if (newSource == row.source.trim() && newTarget == row.target.trim()) return;

    setState(() => _applying = true);
    try {
      await editGlossarySyncRow(
        ref,
        oldRow: row,
        newSource: newSource,
        newTarget: newTarget,
        updateGlossary: resultData!.updateGlossary,
        updateVietPhrase: resultData!.updateVietPhrase,
      );
      if (!mounted) return;
      setState(() {
        _selected.remove(row.source);
        _cachedSource = null;
        _cachedResult = null;
      });
      _showMessage(
        resultData!.updateGlossary && resultData!.updateVietPhrase
            ? 'Đã cập nhật cả 2 bên (Glossary & VietPhrase): $newSource → $newTarget'
            : 'Đã cập nhật: $newSource → $newTarget',
      );
    } catch (_) {
      _showMessage('Có lỗi xảy ra khi lưu.');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _showBulkEditDialog(List<GlossarySyncRow> rows) async {
    if (rows.isEmpty || _applying) return;
    if (rows.length == 1) {
      return _showSingleEditDialog(rows.first);
    }

    final mode = ref.read(translationControllerProvider).mode;
    final lang = GlossaryService.langFor(mode);

    final canApplyNotifier = ValueNotifier<bool>(false);
    _BulkEditResult? resultData;

    final saved = await showAppDialog<bool>(
      context: context,
      icon: Icons.edit_note,
      accentColor: const Color(0xFF00897B),
      title: 'Sửa hàng loạt ${rows.length} mục đã chọn',
      description: 'Chọn chế độ sửa và nơi áp dụng:',
      width: 600,
      content: _BulkEditDialogContent(
        lang: lang,
        canApplyNotifier: canApplyNotifier,
        onChanged: (res) => resultData = res,
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: canApplyNotifier,
          builder: (context, canApply, _) => FilledButton.icon(
            icon: const Icon(Icons.check, size: 18),
            onPressed: canApply ? () => Navigator.pop(dialogContext, true) : null,
            label: Text('Áp dụng ${rows.length} mục'),
          ),
        ),
      ],
    );
    canApplyNotifier.disposeAfterRouteAnimation();

    if (saved != true || resultData == null) return;

    setState(() => _applying = true);
    try {
      await bulkEditGlossarySyncRows(
        ref,
        rows: rows,
        newTarget: resultData!.newTarget,
        isReplaceMode: resultData!.isReplaceMode,
        findText: resultData!.findText,
        replaceText: resultData!.replaceText,
        updateGlossary: resultData!.updateGlossary,
        updateVietPhrase: resultData!.updateVietPhrase,
      );
      if (!mounted) return;
      setState(() {
        for (final r in rows) {
          _selected.remove(r.source);
        }
        _cachedSource = null;
        _cachedResult = null;
      });
      _showMessage(
        resultData!.updateGlossary && resultData!.updateVietPhrase
            ? 'Đã sửa ${rows.length} mục ở cả 2 bên (Glossary & VietPhrase).'
            : 'Đã sửa ${rows.length} mục.',
      );
    } catch (_) {
      _showMessage('Có lỗi xảy ra khi lưu hàng loạt.');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<bool> _confirmBulk(
    int count, {
    required GlossarySyncDirection direction,
  }) async {
    final toGlossary =
        direction == GlossarySyncDirection.vietPhraseToGlossary;
    final confirmed = await showAppDialog<bool>(
      context: context,
      icon: Icons.sync_alt,
      accentColor: _glossaryAccent,
      title: 'Cập nhật $count mục',
      description: direction.label,
      width: 460,
      content: Text(
        toGlossary
            ? '$count mục sẽ được ghi vào Global Glossary với created_by = user. '
                  'Mục đã có sẽ bị ghi đè nghĩa.'
            : '$count mục sẽ được lưu vào VietPhrase cục bộ và xếp hàng chờ. '
                  'Bấm Update trong Cài đặt để gửi lên server.',
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('Cập nhật $count mục (${direction.label})'),
        ),
      ],
    );
    return confirmed == true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final glossaryDir = ref.watch(settingsProvider.select((s) => s.glossaryDir));
    final mode = ref.watch(
      translationControllerProvider.select((state) => state.mode),
    );
    ref.listen(
      translationControllerProvider.select((state) => state.mode),
      (previous, next) {
        if (previous != next) {
          setState(() {
            _selected.clear();
            _page = 0;
            _cachedSource = null;
            _cachedResult = null;
          });
        }
      },
    );
    ref.listen(
      glossarySyncRowsProvider(widget.direction),
      (previous, next) {
        if (next.hasValue) {
          setState(() {
            _cachedSource = null;
            _cachedResult = null;
          });
        }
      },
    );
    if (!GlossaryService(glossaryDir).hasGlossaryFor(mode)) {
      return _CenteredNote(
        'Chưa tìm thấy "Global Glossary.json" của ${GlossaryService.langFor(mode)}.\n'
        'Chọn lại thư mục Glossary trong Cài đặt → Từ điển chung.',
      );
    }

    final rows = ref.watch(glossarySyncRowsProvider(widget.direction));
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CenteredNote('Không đọc được dữ liệu.\n$error'),
      data: (all) {
        final filtered = _filter(all);
        final pageCount = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
        final page = _page.clamp(0, pageCount - 1);
        final start = page * _pageSize;
        final visible = filtered.sublist(
          start,
          (start + _pageSize).clamp(0, filtered.length),
        );

        return Column(
          children: [
            _filterBar(total: all.length, shown: filtered.length),
            const Divider(height: 1),
            _selectionBar(visible),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? const _CenteredNote('Không có mục nào khớp bộ lọc.')
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _RowTile(
                        row: visible[index],
                        selected: _selected.containsKey(visible[index].source),
                        enabled: !_applying,
                        onSelected: (value) => setState(() {
                          final row = visible[index];
                          if (value == true) {
                            _selected[row.source] = row;
                          } else {
                            _selected.remove(row.source);
                          }
                        }),
                        onApply: () => _apply([visible[index]], bulk: false),
                        onEdit: () => _showSingleEditDialog(visible[index]),
                        onDelete: () => _confirmDelete([visible[index]]),
                      ),
                    ),
            ),
            const Divider(height: 1),
            _pager(page: page, pageCount: pageCount, total: filtered.length),
          ],
        );
      },
    );
  }

  Widget _filterBar({required int total, required int shown}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<DuplicateFilter>(
            segments: [
              for (final filter in DuplicateFilter.values)
                ButtonSegment(value: filter, label: Text(filter.label)),
            ],
            selected: {_duplicateFilter},
            onSelectionChanged: (value) => setState(() {
              _duplicateFilter = value.first;
              _page = 0;
            }),
          ),
          if (_hasCreatedByFilter)
            FilterChip(
              label: const Text('created_by = A.I'),
              selected: _createdByAiOnly,
              onSelected: (value) => setState(() {
                _createdByAiOnly = value;
                _page = 0;
              }),
            ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Tìm từ hoặc nghĩa',
              ),
              onChanged: (value) => setState(() {
                _search = value;
                _page = 0;
              }),
            ),
          ),
          Text('$shown / $total mục'),
        ],
      ),
    );
  }

  Widget _selectionBar(List<GlossarySyncRow> visible) {
    final scheme = Theme.of(context).colorScheme;
    final allOnPageSelected =
        visible.isNotEmpty &&
        visible.every((row) => _selected.containsKey(row.source));

    final oppositeDirection =
        widget.direction == GlossarySyncDirection.glossaryToVietPhrase
            ? GlossarySyncDirection.vietPhraseToGlossary
            : GlossarySyncDirection.glossaryToVietPhrase;
    final reverseRows = _getReverseRows(_selected.values);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: allOnPageSelected,
            tristate: false,
            onChanged: visible.isEmpty || _applying
                ? null
                : (value) => setState(() {
                    for (final row in visible) {
                      if (value == true) {
                        _selected[row.source] = row;
                      } else {
                        _selected.remove(row.source);
                      }
                    }
                  }),
          ),
          const Text('Chọn cả trang'),
          const SizedBox(width: 16),
          Text('Đã chọn ${_selected.length}'),
          if (_selected.isNotEmpty) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: _applying ? null : () => setState(_selected.clear),
              child: const Text('Bỏ chọn hết'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('Sửa (${_selected.length})'),
              onPressed: _applying
                  ? null
                  : () => _showBulkEditDialog(_selected.values.toList()),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('Xóa (${_selected.length})'),
              onPressed: _applying
                  ? null
                  : () => _confirmDelete(_selected.values.toList()),
            ),
          ],
          const Spacer(),
          FilledButton.icon(
            icon: _applying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward, size: 18),
            label: Text('${widget.direction.label} (${_selected.length})'),
            onPressed: _selected.isEmpty || _applying
                ? null
                : () => _apply(_selected.values.toList(), bulk: true),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.tertiary,
              foregroundColor: scheme.onTertiary,
            ),
            icon: _applying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_back, size: 18),
            label: Text('${oppositeDirection.label} (${reverseRows.length})'),
            onPressed: _selected.isEmpty || reverseRows.isEmpty || _applying
                ? null
                : () => _apply(
                      reverseRows,
                      bulk: true,
                      customDirection: oppositeDirection,
                    ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _pager({
    required int page,
    required int pageCount,
    required int total,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('Số mục mỗi trang'),
          const SizedBox(width: 10),
          DropdownButton<int>(
            value: _pageSize,
            items: [
              for (final size in _pageSizes)
                DropdownMenuItem(value: size, child: Text('$size')),
            ],
            onChanged: (value) => setState(() {
              _pageSize = value ?? 50;
              _page = 0;
            }),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.first_page),
            tooltip: 'Trang đầu',
            onPressed: page == 0 ? null : () => _resetPaging(),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Trang trước',
            onPressed: page == 0 ? null : () => setState(() => _page = page - 1),
          ),
          Text('Trang ${page + 1} / $pageCount  ($total mục)'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Trang sau',
            onPressed: page >= pageCount - 1
                ? null
                : () => setState(() => _page = page + 1),
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            tooltip: 'Trang cuối',
            onPressed: page >= pageCount - 1
                ? null
                : () => setState(() => _page = pageCount - 1),
          ),
        ],
      ),
    );
  }
}

/// Một dòng: từ nguồn, giá trị sẽ ghi, và giá trị đang có bên đích nếu trùng.
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
  });

  final GlossarySyncRow row;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final other = row.otherTarget;

    return CheckboxListTile(
      value: selected,
      onChanged: enabled ? onSelected : null,
      controlAffinity: ListTileControlAffinity.leading,
      isThreeLine: other != null,
      title: Row(
        children: [
          Expanded(
            child: Text(
              row.source,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (row.createdBy.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(row.createdBy),
                labelStyle: Theme.of(context).textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.target),
          if (other != null)
            Text(
              row.isIdentical
                  ? 'Bên kia đã có, giống hệt: $other'
                  : 'Bên kia đang là: $other  →  sẽ ghi đè',
              style: TextStyle(
                color: row.isIdentical ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
        ],
      ),
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Sửa mục này',
            onPressed: enabled ? onEdit : null,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: enabled ? scheme.error : null,
            ),
            tooltip: 'Xóa mục này',
            onPressed: enabled ? onDelete : null,
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Cập nhật'),
            onPressed: enabled ? onApply : null,
          ),
        ],
      ),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

extension _ValueNotifierX on ValueNotifier<dynamic> {
  void disposeAfterRouteAnimation() {
    Future<void>.delayed(const Duration(milliseconds: 500), dispose);
  }
}

class _ConfirmDeleteResult {
  const _ConfirmDeleteResult({
    required this.deleteFromGlossary,
    required this.deleteFromVietPhrase,
  });

  final bool deleteFromGlossary;
  final bool deleteFromVietPhrase;
}

class _ConfirmDeleteDialogContent extends StatefulWidget {
  const _ConfirmDeleteDialogContent({
    required this.lang,
    required this.canDeleteNotifier,
    required this.onChanged,
  });

  final String lang;
  final ValueNotifier<bool> canDeleteNotifier;
  final ValueChanged<_ConfirmDeleteResult> onChanged;

  @override
  State<_ConfirmDeleteDialogContent> createState() =>
      _ConfirmDeleteDialogContentState();
}

class _ConfirmDeleteDialogContentState
    extends State<_ConfirmDeleteDialogContent> {
  bool _deleteFromGlossary = true;
  bool _deleteFromVietPhrase = true;

  @override
  void initState() {
    super.initState();
    _notify();
  }

  void _notify() {
    widget.canDeleteNotifier.value =
        _deleteFromGlossary || _deleteFromVietPhrase;
    widget.onChanged(
      _ConfirmDeleteResult(
        deleteFromGlossary: _deleteFromGlossary,
        deleteFromVietPhrase: _deleteFromVietPhrase,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: _deleteFromGlossary,
          title: Text('Xóa khỏi Global Glossary (${widget.lang})'),
          subtitle: const Text('Ghi trực tiếp vào file Global Glossary.json'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _deleteFromGlossary = v ?? false;
            _notify();
          }),
        ),
        CheckboxListTile(
          value: _deleteFromVietPhrase,
          title: const Text('Xóa khỏi VietPhrase cục bộ'),
          subtitle: const Text(
            'Xếp hàng xóa VietPhrase (bấm Update để gửi lên server)',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _deleteFromVietPhrase = v ?? false;
            _notify();
          }),
        ),
      ],
    );
  }
}

class _SingleEditResult {
  const _SingleEditResult({
    required this.newSource,
    required this.newTarget,
    required this.updateGlossary,
    required this.updateVietPhrase,
  });

  final String newSource;
  final String newTarget;
  final bool updateGlossary;
  final bool updateVietPhrase;
}

class _SingleEditDialogContent extends StatefulWidget {
  const _SingleEditDialogContent({
    required this.row,
    required this.lang,
    required this.canSaveNotifier,
    required this.onChanged,
  });

  final GlossarySyncRow row;
  final String lang;
  final ValueNotifier<bool> canSaveNotifier;
  final ValueChanged<_SingleEditResult> onChanged;

  @override
  State<_SingleEditDialogContent> createState() =>
      _SingleEditDialogContentState();
}

class _SingleEditDialogContentState extends State<_SingleEditDialogContent> {
  late final TextEditingController _sourceController;
  late final TextEditingController _targetController;
  bool _updateGlossary = true;
  bool _updateVietPhrase = true;

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController(text: widget.row.source);
    _targetController = TextEditingController(text: widget.row.target);
    _notify();
  }

  void _notify() {
    final newSource = _sourceController.text.trim();
    final newTarget = _targetController.text.trim();
    widget.canSaveNotifier.value =
        newSource.isNotEmpty &&
        newTarget.isNotEmpty &&
        (_updateGlossary || _updateVietPhrase);
    widget.onChanged(
      _SingleEditResult(
        newSource: newSource,
        newTarget: newTarget,
        updateGlossary: _updateGlossary,
        updateVietPhrase: _updateVietPhrase,
      ),
    );
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _sourceController,
          decoration: const InputDecoration(labelText: 'Từ nguồn'),
          onChanged: (_) => _notify(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _targetController,
          decoration: const InputDecoration(labelText: 'Nghĩa tiếng Việt'),
          onChanged: (_) => _notify(),
        ),
        const SizedBox(height: 16),
        const Text(
          'Áp dụng thay đổi vào:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        CheckboxListTile(
          value: _updateGlossary,
          title: Text('Cập nhật Global Glossary (${widget.lang})'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _updateGlossary = v ?? false;
            _notify();
          }),
        ),
        CheckboxListTile(
          value: _updateVietPhrase,
          title: const Text('Cập nhật VietPhrase cục bộ'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _updateVietPhrase = v ?? false;
            _notify();
          }),
        ),
      ],
    );
  }
}

class _BulkEditResult {
  const _BulkEditResult({
    required this.isReplaceMode,
    required this.newTarget,
    required this.findText,
    required this.replaceText,
    required this.updateGlossary,
    required this.updateVietPhrase,
  });

  final bool isReplaceMode;
  final String newTarget;
  final String findText;
  final String replaceText;
  final bool updateGlossary;
  final bool updateVietPhrase;
}

class _BulkEditDialogContent extends StatefulWidget {
  const _BulkEditDialogContent({
    required this.lang,
    required this.canApplyNotifier,
    required this.onChanged,
  });

  final String lang;
  final ValueNotifier<bool> canApplyNotifier;
  final ValueChanged<_BulkEditResult> onChanged;

  @override
  State<_BulkEditDialogContent> createState() => _BulkEditDialogContentState();
}

class _BulkEditDialogContentState extends State<_BulkEditDialogContent> {
  late final TextEditingController _newTargetController;
  late final TextEditingController _findTextController;
  late final TextEditingController _replaceTextController;
  bool _isReplaceMode = false;
  bool _updateGlossary = true;
  bool _updateVietPhrase = true;

  @override
  void initState() {
    super.initState();
    _newTargetController = TextEditingController();
    _findTextController = TextEditingController();
    _replaceTextController = TextEditingController();
    _notify();
  }

  void _notify() {
    final textOk = !_isReplaceMode
        ? _newTargetController.text.trim().isNotEmpty
        : _findTextController.text.isNotEmpty;
    widget.canApplyNotifier.value =
        (_updateGlossary || _updateVietPhrase) && textOk;
    widget.onChanged(
      _BulkEditResult(
        isReplaceMode: _isReplaceMode,
        newTarget: _newTargetController.text.trim(),
        findText: _findTextController.text,
        replaceText: _replaceTextController.text,
        updateGlossary: _updateGlossary,
        updateVietPhrase: _updateVietPhrase,
      ),
    );
  }

  @override
  void dispose() {
    _newTargetController.dispose();
    _findTextController.dispose();
    _replaceTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Đặt nghĩa mới')),
            ButtonSegment(value: true, label: Text('Thay thế chuỗi')),
          ],
          selected: {_isReplaceMode},
          onSelectionChanged: (v) => setState(() {
            _isReplaceMode = v.first;
            _notify();
          }),
        ),
        const SizedBox(height: 16),
        if (!_isReplaceMode)
          TextField(
            controller: _newTargetController,
            decoration: const InputDecoration(
              labelText: 'Nghĩa mới cho tất cả mục',
              hintText: 'Nhập nghĩa tiếng Việt mới',
            ),
            onChanged: (_) => _notify(),
          )
        else ...[
          TextField(
            controller: _findTextController,
            decoration: const InputDecoration(
              labelText: 'Chuỗi cần tìm trong nghĩa',
              hintText: 'Cần tìm...',
            ),
            onChanged: (_) => _notify(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _replaceTextController,
            decoration: const InputDecoration(
              labelText: 'Thay thế bằng',
              hintText: 'Thay thế...',
            ),
            onChanged: (_) => _notify(),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Áp dụng thay đổi vào:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        CheckboxListTile(
          value: _updateGlossary,
          title: Text('Cập nhật Global Glossary (${widget.lang})'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _updateGlossary = v ?? false;
            _notify();
          }),
        ),
        CheckboxListTile(
          value: _updateVietPhrase,
          title: const Text('Cập nhật VietPhrase cục bộ'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _updateVietPhrase = v ?? false;
            _notify();
          }),
        ),
      ],
    );
  }
}

