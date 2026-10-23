import 'package:flutter/material.dart';

import '../domain/project_segment.dart';

class ProjectSegmentEditor extends StatefulWidget {
  const ProjectSegmentEditor({
    super.key,
    required this.segment,
    required this.onChanged,
    required this.onReviewed,
    required this.onSuggestion,
  });

  final ProjectSegment segment;
  final ValueChanged<String> onChanged;
  final VoidCallback onReviewed;
  final VoidCallback onSuggestion;

  @override
  State<ProjectSegmentEditor> createState() => _ProjectSegmentEditorState();
}

class _ProjectSegmentEditorState extends State<ProjectSegmentEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.segment.editedTarget);
  }

  @override
  void didUpdateWidget(covariant ProjectSegmentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.segment.editedTarget != _controller.text) {
      final selection = _controller.selection;
      final newText = widget.segment.editedTarget;
      _controller.value = TextEditingValue(
        text: newText,
        selection: selection.isValid && selection.end <= newText.length
            ? selection
            : TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.segment;
    final reviewed = segment.status == ProjectSegmentStatus.reviewed;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(segment.source, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'VietPhrase: ${segment.machineOutput}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey(segment.segmentId),
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Bản dịch của bạn',
                border: OutlineInputBorder(),
              ),
              onChanged: widget.onChanged,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (segment.editedTarget.trim().isEmpty)
                  TextButton.icon(
                    onPressed: widget.onSuggestion,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Gợi ý TM'),
                  ),
                const Spacer(),
                if (reviewed)
                  const Chip(
                    avatar: Icon(Icons.check, size: 16),
                    label: Text('Đã duyệt'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: segment.editedTarget.trim().isEmpty
                        ? null
                        : widget.onReviewed,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Đánh dấu đã duyệt'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
