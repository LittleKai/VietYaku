import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../../dictionary/data/user_dict_service.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../translation/application/token_selection.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/presentation/lacviet_panel.dart' show meaningLabelColor;
import '../../translation/presentation/source_pane.dart';
import '../application/coverage_report_provider.dart';
import '../domain/coverage_report.dart';

const _accent = Color(0xFF00838F);

/// Dialog "Kiểm tra": độ phủ từ điển của văn bản đang mở, bảng cụm chưa dịch
/// xếp theo tần suất, và danh sách ứng viên tên riêng nhập nghĩa hàng loạt.
Future<void> showCoverageReportDialog(BuildContext context) {
  return showAppDialog<void>(
    context: context,
    icon: Icons.fact_check_outlined,
    accentColor: _accent,
    title: 'Kiểm tra bản dịch',
    description: 'Độ phủ từ điển và những cụm chưa dịch của văn bản đang mở.',
    width: 760,
    content: const _CoverageBody(),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Đóng'),
      ),
    ],
  );
}

enum _AddTarget { vietPhrase, lacViet, userDict, names }

class _CoverageBody extends ConsumerStatefulWidget {
  const _CoverageBody();

  @override
  ConsumerState<_CoverageBody> createState() => _CoverageBodyState();
}

class _CoverageBodyState extends ConsumerState<_CoverageBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _nameControllers = <String, TextEditingController>{};
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String word) =>
      _nameControllers.putIfAbsent(word, TextEditingController.new);

  /// Bấm một dòng → tô nổi cụm ở cả 3 ô, cuộn ô Nguồn tới đó, đóng dialog.
  void _jumpTo(int start, String word) {
    ref
        .read(tokenSelectionProvider.notifier)
        .selectRange(start, start + word.length, word);
    requestSourceScroll(ref, start);
    Navigator.pop(context);
  }

  /// Chuột phải một dòng → chọn từ điển đích rồi mở thẳng dialog sửa entry.
  Future<void> _showAddMenu(Offset globalPosition, String word) async {
    final scheme = Theme.of(context).colorScheme;
    final isAdmin = ref.read(dictionarySyncProvider).isAdmin;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final target = await showMenu<_AddTarget>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        if (isAdmin) ...[
          _menuItem(
            _AddTarget.vietPhrase,
            Icons.menu_book_outlined,
            'Thêm vào VietPhrase',
            meaningLabelColor('VietPhrase', scheme),
          ),
          _menuItem(
            _AddTarget.lacViet,
            Icons.local_library_outlined,
            'Thêm vào Lạc Việt',
            meaningLabelColor('Lạc Việt', scheme),
          ),
        ] else
          _menuItem(
            _AddTarget.userDict,
            Icons.person_add_alt_1_outlined,
            'Thêm vào UserDict',
            meaningLabelColor('UserDict', scheme),
          ),
        _menuItem(
          _AddTarget.names,
          Icons.badge_outlined,
          'Thêm vào Names',
          meaningLabelColor('Names', scheme),
        ),
      ],
    );
    if (target == null || !mounted) return;
    switch (target) {
      case _AddTarget.vietPhrase:
        await showSharedEntryEditDialog(
          context,
          ref,
          word: word,
          kind: SharedDictionaryKind.vietPhrase,
        );
      case _AddTarget.lacViet:
        await showSharedEntryEditDialog(
          context,
          ref,
          word: word,
          kind: SharedDictionaryKind.lacViet,
        );
      case _AddTarget.userDict:
        await showEntryEditDialog(
          context,
          ref,
          word: word,
          toNames: false,
          title: 'Thêm vào UserDict',
        );
      case _AddTarget.names:
        await showEntryEditDialog(
          context,
          ref,
          word: word,
          toNames: true,
          title: 'Thêm vào Names',
        );
    }
  }

  PopupMenuItem<_AddTarget> _menuItem(
    _AddTarget value,
    IconData icon,
    String label,
    Color color,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label),
      ],
    ),
  );

  /// Ghi mọi ô nghĩa đã điền vào UserNames một lượt, rồi nạp lại dict + dịch lại.
  Future<void> _saveNames(List<UnmatchedChunk> candidates) async {
    final entries = <String, String>{};
    for (final candidate in candidates) {
      final meaning = _nameControllers[candidate.source]?.text.trim() ?? '';
      if (meaning.isNotEmpty) entries[candidate.source] = meaning;
    }
    if (entries.isEmpty) return;
    setState(() => _saving = true);
    try {
      final paths = await ref.read(appPathsProvider.future);
      await UserDictService(paths).upsertUserNames(entries);
      await ref.read(dictionariesProvider.notifier).reload();
      final translation = ref.read(translationControllerProvider);
      if (translation.sourceText.isNotEmpty) {
        ref
            .read(translationControllerProvider.notifier)
            .translate(translation.sourceText);
      }
      for (final key in entries.keys) {
        _nameControllers[key]?.clear();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Đã lưu ${entries.length} tên vào Names.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(coverageReportProvider);
    if (report == null) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('Chưa có kết quả dịch — bấm Dịch Lại rồi mở lại.'),
        ),
      );
    }
    return SizedBox(
      height: 440,
      child: Column(
        children: [
          _Stats(report: report),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Chưa dịch (${report.chunks.length})'),
              Tab(text: 'Tên riêng (${report.nameCandidates.length})'),
              Tab(text: 'Không nhất quán (${report.inconsistentTerms.length})'),
              Tab(text: 'Cảnh báo (${report.warnings.length})'),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _tabController.index,
              sizing: StackFit.expand,
              children: [
                _buildChunkList(report),
                _buildNameList(report),
                _buildInconsistentList(report),
                _buildWarningList(report),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChunkList(CoverageReport report) {
    if (report.chunks.isEmpty) {
      return const Center(child: Text('Không còn cụm nào chưa dịch.'));
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Bấm một dòng để nhảy tới chỗ nó xuất hiện · chuột phải để thêm vào từ điển.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: report.chunks.length,
            itemBuilder: (context, index) {
              final chunk = report.chunks[index];
              return _ChunkRow(
                chunk: chunk,
                onTap: () => _jumpTo(chunk.firstStart, chunk.source),
                onSecondaryTap: (position) =>
                    _showAddMenu(position, chunk.source),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNameList(CoverageReport report) {
    final candidates = report.nameCandidates;
    if (candidates.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Không có cụm nào lặp đủ $minNameOccurrences lần để coi là tên riêng.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Cụm lặp ≥ $minNameOccurrences lần, không có trong Names lẫn VietPhrase. '
            'Điền nghĩa rồi lưu một lượt.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        candidate.source,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _CountBadge(count: candidate.count),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _controllerFor(candidate.source),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Nghĩa…',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              onPressed: _saving ? null : () => _saveNames(candidates),
              label: const Text('Lưu vào Names'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInconsistentList(CoverageReport report) {
    if (report.inconsistentTerms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Mọi cụm đều được cắt giống nhau ở mọi chỗ.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Cùng một chuỗi, chỗ thì dịch nguyên cụm, chỗ khác lại bị cắt nhỏ. '
            'Bấm để nhảy tới chỗ đó.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: report.inconsistentTerms.length,
            itemBuilder: (context, index) {
              final term = report.inconsistentTerms[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SegmentationRow(
                      segmentation: term.source,
                      meaning: term.meaning,
                      count: term.count,
                      primary: true,
                      onTap: () => _jumpTo(term.firstStart, term.source),
                    ),
                    for (final variant in term.variants)
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: _SegmentationRow(
                          segmentation: variant.segmentation,
                          meaning: variant.meaning,
                          count: variant.count,
                          primary: false,
                          onTap: () =>
                              _jumpTo(variant.firstStart, term.source),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWarningList(CoverageReport report) {
    if (report.warnings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ngoặc cân bằng, không có số nào bị mất.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: report.warnings.length,
      itemBuilder: (context, index) {
        final warning = report.warnings[index];
        return InkWell(
          onTap: () => _jumpTo(warning.offset, warning.excerpt),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(
                  warning.kind == TextWarningKind.missingNumber
                      ? Icons.pin_outlined
                      : Icons.data_array_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(_warningMessage(warning))),
                Text(
                  'vị trí ${_n(warning.offset)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _warningMessage(TextWarning warning) => switch (warning.kind) {
  TextWarningKind.unclosedBracket =>
    'Ngoặc ${warning.excerpt} mở mà không có ngoặc đóng',
  TextWarningKind.strayCloseBracket =>
    'Ngoặc đóng ${warning.excerpt} không khớp ngoặc mở nào',
  TextWarningKind.missingNumber =>
    'Số ${warning.excerpt} có trong nguồn nhưng mất trong bản dịch',
};

/// Một cách cắt cụm: `nguồn → nghĩa ×count`. [primary] là cách cắt nguyên cụm.
class _SegmentationRow extends StatelessWidget {
  const _SegmentationRow({
    required this.segmentation,
    required this.meaning,
    required this.count,
    required this.primary,
    required this.onTap,
  });

  final String segmentation;
  final String meaning;
  final int count;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            if (!primary) ...[
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: segmentation,
                      style: TextStyle(
                        fontWeight: primary
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '  →  $meaning',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _CountBadge(count: count),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.report});

  final CoverageReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = report.totalCjk == 0
        ? '—'
        : '${(report.coverage * 100).toStringAsFixed(1)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              percent,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_n(report.matchedCjk)} / ${_n(report.totalCjk)} ký tự CJK đã match từ điển\n'
                  '${_n(report.chunks.length)} cụm chưa dịch · ${_n(report.totalOccurrences)} lượt · '
                  '${_n(report.uncoveredCjk)} ký tự còn thiếu',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: report.coverage,
            minHeight: 7,
            color: _accent,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _ChunkRow extends StatelessWidget {
  const _ChunkRow({
    required this.chunk,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final UnmatchedChunk chunk;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chunk.source,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _CountBadge(count: chunk.count),
              SizedBox(
                width: 96,
                child: Text(
                  'vị trí ${_n(chunk.firstStart)}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        '×$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _accent,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Số nguyên có dấu chấm ngăn hàng nghìn, đúng kiểu số liệu dùng trong app.
String _n(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
