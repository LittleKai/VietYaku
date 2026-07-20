import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../dictionary/domain/dict_type.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/translation_engine.dart';
import '../application/repair_controller.dart';

class RepairScreen extends ConsumerWidget {
  const RepairScreen({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repairControllerProvider);
    final notifier = ref.read(repairControllerProvider.notifier);
    final mode = ref.watch(currentModeProvider);
    final settings = ref.watch(settingsProvider);
    final paths = settings.dictPathsFor(mode);
    final report = state.report;
    final modeLabel = mode == TranslationMode.japanese ? 'Nhật' : 'Trung';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Text(
              'Sửa từ điển ($modeLabel)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Chọn 1 file trong bộ data/${modeDirNames[mode]} để sửa key '
              '(xóa space + simp→JP). Chính sách "Key thuần Hán" chỉnh trong '
              'Cài đặt.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              DropdownMenu<DictType>(
                width: 340,
                enabled: !state.running,
                label: const Text('File từ điển'),
                onSelected: (type) {
                  if (type != null) notifier.pickFile(paths[type]!);
                },
                dropdownMenuEntries: [
                  for (final type in dictFileNames.keys)
                    DropdownMenuEntry(value: type, label: dictFileNames[type]!),
                ],
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
          if (state.filePath != null) ...[
            const SizedBox(height: 8),
            Text(
              state.filePath!,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (state.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: state.progress),
          ],
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          if (report != null) _ReportCard(state: state, notifier: notifier),
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
                  'Conflict (giữ dòng đầu) — ${report.conflicts.length}',
                ),
                children: [
                  for (final c in report.conflicts.take(100))
                    ListTile(
                      dense: true,
                      title: Text(
                        c,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            if (report.ambiguous.isNotEmpty)
              ExpansionTile(
                dense: true,
                title: Text(
                  'Ambiguous (không convert) — ${report.ambiguous.length}',
                ),
                children: [
                  for (final e in report.ambiguous.entries)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${e.key} → ${e.value}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.save),
                  label: Text(
                    state.exportedPath == null
                        ? 'Xuất file _JP.txt'
                        : 'Đã xuất: ${p.basename(state.exportedPath!)}',
                  ),
                  onPressed: state.exportedPath == null
                      ? notifier.export
                      : null,
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
