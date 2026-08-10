import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// Nút `?` mở giải thích ngắn cho một tính năng phức tạp.
class FeatureHelpButton extends StatelessWidget {
  const FeatureHelpButton({
    super.key,
    required this.title,
    required this.summary,
    required this.points,
    this.accentColor,
    this.tooltip = 'Giải thích tính năng',
  });

  final String title;
  final String summary;
  final List<String> points;
  final Color? accentColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => showAppDialog<void>(
        context: context,
        icon: Icons.help_outline,
        title: title,
        description: summary,
        accentColor: accentColor,
        width: 620,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < points.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == points.length - 1 ? 0 : 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            (accentColor ??
                                    Theme.of(context).colorScheme.primary)
                                .withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color:
                                  accentColor ??
                                  Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(points[index])),
                  ],
                ),
              ),
          ],
        ),
        actionsBuilder: (dialogContext) => [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }
}
