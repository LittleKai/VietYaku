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
          const Spacer(),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _applying ? null : () => setState(_selected.clear),
              child: const Text('Bỏ chọn hết'),
            ),
          const SizedBox(width: 8),
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
  });

  final GlossarySyncRow row;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onApply;

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
      secondary: TextButton.icon(
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Cập nhật'),
        onPressed: enabled ? onApply : null,
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
