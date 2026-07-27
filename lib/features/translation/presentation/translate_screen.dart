import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../application/translation_controller.dart';
import '../domain/translation_engine.dart';
import 'han_viet_pane.dart';
import 'lacviet_panel.dart';
import 'result_pane.dart';
import 'source_pane.dart';
import 'viet_pane.dart';

/// Bố cục kiểu QuickTranslator, 2 cột, mỗi ô kéo được (chiều cao trong cột +
/// bề rộng giữa 2 cột). Trái: [Nguồn | Hán Việt] tabs trên, ô Nghĩa dưới.
/// Phải: VietPhrase trên, ô Bản dịch Việt dưới. Tỷ lệ được lưu để khôi phục.
class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> {
  @override
  Widget build(BuildContext context) {
    final dicts = ref.watch(dictionariesProvider);
    final columns = ref.watch(settingsProvider.select((s) => s.columnsRatio));
    final left = ref.watch(settingsProvider.select((s) => s.leftSplitRatio));
    final right = ref.watch(settingsProvider.select((s) => s.rightSplitRatio));
    final notifier = ref.read(settingsProvider.notifier);

    final leftColumn = _DraggableSplit(
      axis: Axis.vertical,
      ratio: left,
      onChangedEnd: (v) => notifier.setLayoutRatio('left', v),
      first: const _SourceTabs(),
      second: const LacVietPanel(),
    );

    final rightColumn = _DraggableSplit(
      axis: Axis.vertical,
      ratio: right,
      onChangedEnd: (v) => notifier.setLayoutRatio('right', v),
      first: const ResultPane(),
      second: const VietPane(),
    );

    return Column(
      children: [
        const _MenuBar(),
        const Divider(height: 1, thickness: 1),
        if (dicts.isLoading)
          const LinearProgressIndicator(minHeight: 3)
        else if (dicts.hasError)
          MaterialBanner(
            content: Text('Lỗi nạp từ điển: ${dicts.error}'),
            actions: [
              TextButton(
                onPressed: () => ref.invalidate(dictionariesProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        Expanded(
          child: _DraggableSplit(
            axis: Axis.horizontal,
            ratio: columns,
            onChangedEnd: (v) => notifier.setLayoutRatio('columns', v),
            first: leftColumn,
            second: rightColumn,
          ),
        ),
      ],
    );
  }
}

/// Chia hai ô theo [axis] với thanh kéo ở giữa; [ratio] là tỷ lệ ô đầu tiên.
/// Stateful để khi kéo chỉ rebuild ô chia (không rebuild cả màn hình/provider).
class _DraggableSplit extends StatefulWidget {
  const _DraggableSplit({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
    required this.onChangedEnd,
  });

  final Axis axis;
  final double ratio;
  final Widget first;
  final Widget second;
  final ValueChanged<double> onChangedEnd;

  @override
  State<_DraggableSplit> createState() => _DraggableSplitState();
}

class _DraggableSplitState extends State<_DraggableSplit> {
  static const _handle = 8.0;
  late double _ratio = widget.ratio;

  @override
  void didUpdateWidget(_DraggableSplit old) {
    super.didUpdateWidget(old);
    // Đồng bộ khi tỷ lệ lưu đổi từ ngoài (không phải do kéo).
    if (widget.ratio != old.ratio) _ratio = widget.ratio;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final avail = (total - _handle).clamp(1.0, double.infinity);
        final firstSize = (avail * _ratio).clamp(avail * 0.15, avail * 0.85);

        // Cộng dồn delta trực tiếp vào _ratio: nhiều sự kiện move trong 1 frame
        // đều tích luỹ (nếu tính lại từ firstSize cũ sẽ mất delta → kéo bị chậm).
        void drag(double delta) {
          setState(() => _ratio = (_ratio + delta / avail).clamp(0.15, 0.85));
        }

        final divider = MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: horizontal ? (d) => drag(d.delta.dx) : null,
            onHorizontalDragEnd: horizontal
                ? (_) => widget.onChangedEnd(_ratio)
                : null,
            onVerticalDragUpdate: horizontal ? null : (d) => drag(d.delta.dy),
            onVerticalDragEnd: horizontal
                ? null
                : (_) => widget.onChangedEnd(_ratio),
            child: Center(
              child: Container(
                width: horizontal ? 1 : double.infinity,
                height: horizontal ? double.infinity : 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        );

        final children = <Widget>[
          SizedBox(
            width: horizontal ? firstSize : null,
            height: horizontal ? null : firstSize,
            child: RepaintBoundary(child: widget.first),
          ),
          SizedBox(
            width: horizontal ? _handle : null,
            height: horizontal ? null : _handle,
            child: divider,
          ),
          Expanded(child: RepaintBoundary(child: widget.second)),
        ];

        return horizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }
}

/// Menu bar trên cùng: chọn ngôn ngữ Nhật/Trung + Dịch Lại + Dán & Dịch.
class _MenuBar extends ConsumerWidget {
  const _MenuBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      translationControllerProvider.select((s) => s.mode),
    );
    final dictsLoading = ref.watch(dictionariesProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isJapanese = mode == TranslationMode.japanese;

    // Màu sắc nổi bật riêng biệt cho 2 mode:
    // Nhật: Chế độ Xanh lá nhạt (sáng 0xFF43A047, tối 0xFF66BB6A)
    // Trung: Chế độ Crimson/Flame Amber (sáng 0xFFD84315, tối 0xFFFF7043)
    final modeColor = isJapanese
        ? (isDark ? const Color(0xFF66BB6A) : const Color(0xFF43A047))
        : (isDark ? const Color(0xFFFF7043) : const Color(0xFFD84315));

    // Màu sắc riêng cho nút Dán & Dịch (Teal Emerald) khác nút Dịch Lại (Primary Indigo)
    final pasteBtnBg = isDark
        ? const Color(0xFF00897B)
        : const Color(0xFF00796B);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<TranslationMode>(
                segments: const [
                  ButtonSegment(
                    value: TranslationMode.japanese,
                    label: Text('Nhật', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  ButtonSegment(
                    value: TranslationMode.chinese,
                    label: Text('Trung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return modeColor;
                    }
                    return null;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return null;
                  }),
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return BorderSide(color: modeColor, width: 1.5);
                    }
                    return null;
                  }),
                ),
                onSelectionChanged: (selection) => ref
                    .read(translationControllerProvider.notifier)
                    .setMode(selection.first),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: modeColor.withValues(alpha: isDark ? 0.5 : 0.3),
                  ),
                ),
                child: Text(
                  isJapanese ? 'Nhật → Việt' : 'Trung → Việt',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: modeColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Dịch Lại', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                onPressed: dictsLoading
                    ? null
                    : () => ref
                          .read(translationControllerProvider.notifier)
                          .translate(ref.read(sourceDraftProvider)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.paste_rounded, size: 16),
                label: const Text('Dán & Dịch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                onPressed: dictsLoading
                    ? null
                    : () => ref
                          .read(translationControllerProvider.notifier)
                          .pasteAndTranslate(),
                style: FilledButton.styleFrom(
                  backgroundColor: pasteBtnBg,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
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

/// Tabs [Nguồn | Hán Việt] dùng IndexedStack để giữ state SourcePane
/// (text đang gõ, clipboard watcher) khi đổi tab. Hàng chọn ngôn ngữ
/// Nhật/Trung nằm TRÊN tabs.
class _SourceTabs extends ConsumerStatefulWidget {
  const _SourceTabs();

  @override
  ConsumerState<_SourceTabs> createState() => _SourceTabsState();
}

class _SourceTabsState extends ConsumerState<_SourceTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Nguồn'),
            Tab(text: 'Hán Việt'),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _tabController.index,
            children: const [SourcePane(), HanVietPane()],
          ),
        ),
      ],
    );
  }
}
