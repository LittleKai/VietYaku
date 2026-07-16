import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/repair_controller.dart';
import '../domain/jp_repair_pipeline.dart';
import 'repair_preview.dart';

class RepairScreen extends ConsumerWidget {
  const RepairScreen({super.key});

  Future<void> _pickFile(WidgetRef ref) async {
    const typeGroup = XTypeGroup(label: 'Text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await ref.read(repairControllerProvider.notifier).pickFile(file.path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repairControllerProvider);
    final notifier = ref.read(repairControllerProvider.notifier);
    final report = state.report;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Chọn file từ điển'),
                onPressed: state.running ? null : () => _pickFile(ref),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(state.filePath ?? 'Chưa chọn file',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Key thuần Hán: '),
              const SizedBox(width: 8),
              SegmentedButton<RepairPolicy>(
                segments: const [
                  ButtonSegment(
                    value: RepairPolicy.addVariant,
                    label: Text('Giữ gốc + thêm bản JP'),
                  ),
                  ButtonSegment(
                    value: RepairPolicy.convert,
                    label: Text('Convert hết'),
                  ),
                  ButtonSegment(
                    value: RepairPolicy.keepOnly,
                    label: Text('Không convert'),
                  ),
                ],
                selected: {state.policy},
                onSelectionChanged: state.running
                    ? null
                    : (selection) => notifier.setPolicy(selection.first),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.build),
                label: const Text('Run'),
                onPressed: state.fileContent == null || state.running
                    ? null
                    : notifier.run,
              ),
            ],
          ),
          if (state.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: state.progress),
          ],
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(state.error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          if (report != null) _ReportCard(state: state, notifier: notifier),
          const SizedBox(height: 8),
          Text(
            report == null
                ? 'Preview (50 dòng thay đổi đầu tiên):'
                : 'Preview:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: state.fileContent == null
                  ? const Center(child: Text('Chọn file để xem preview'))
                  : RepairPreview(pairs: state.preview),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  final RepairState state;
  final RepairController notifier;

  const _ReportCard({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = state.report!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('Space đã xóa: ${report.spacesRemoved}'),
                Text('Ký tự đã convert: ${report.charsConverted}'),
                Text('Dòng variant thêm: ${report.variantsAdded}'),
                Text('Trùng lặp bỏ: ${report.dupesIdenticalValue}'),
                Text('Conflict: ${report.conflicts.length}'),
                Text('Ambiguous: ${report.ambiguous.length}'),
              ],
            ),
            if (report.conflicts.isNotEmpty)
              ExpansionTile(
                dense: true,
                title: Text(
                    'Conflict (giữ dòng đầu) — ${report.conflicts.length}'),
                children: [
                  for (final c in report.conflicts.take(100))
                    ListTile(
                        dense: true,
                        title: Text(c,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            if (report.ambiguous.isNotEmpty)
              ExpansionTile(
                dense: true,
                title: Text(
                    'Ambiguous (không convert) — ${report.ambiguous.length}'),
                children: [
                  for (final e in report.ambiguous.entries)
                    ListTile(
                        dense: true,
                        title: Text('${e.key} → ${e.value}',
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.save),
                  label: Text(state.exportedPath == null
                      ? 'Xuất file _JP.txt'
                      : 'Đã xuất: ${p.basename(state.exportedPath!)}'),
                  onPressed:
                      state.exportedPath == null ? notifier.export : null,
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.download_done),
                  label: const Text('Nạp vào app'),
                  onPressed: notifier.loadIntoApp,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
