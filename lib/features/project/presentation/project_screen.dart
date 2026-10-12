import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/project_controller.dart';
import 'project_segment_editor.dart';

class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key});

  Future<void> _open(WidgetRef ref) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Văn bản', extensions: ['txt']),
      ],
    );
    if (file != null) {
      await ref
          .read(projectControllerProvider.notifier)
          .openSourcePath(file.path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectControllerProvider);
    final document = state.document;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.segment, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Project TXT',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _open(ref),
                icon: const Icon(Icons.folder_open),
                label: const Text('Mở file TXT'),
              ),
              if (document != null) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(projectControllerProvider.notifier).save(),
                  icon: const Icon(Icons.save),
                  label: const Text('Lưu project'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (document == null)
            const Expanded(child: Center(child: Text('Chưa mở project')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: document.segments.length,
                itemBuilder: (context, index) {
                  final segment = document.segments[index];
                  final controller = ref.read(
                    projectControllerProvider.notifier,
                  );
                  return ProjectSegmentEditor(
                    segment: segment,
                    onChanged: (value) => controller.setTarget(index, value),
                    onReviewed: () => controller.markReviewed(index),
                    onSuggestion: () => controller.applyTmSuggestion(index),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
