import 'package:flutter/material.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? description,
  required Widget content,
  required List<Widget> Function(BuildContext dialogContext) actionsBuilder,
  double width = 520,
  Color? accentColor,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => AppDialog(
      icon: icon,
      title: title,
      description: description,
      width: width,
      accentColor: accentColor,
      actions: actionsBuilder(dialogContext),
      child: content,
    ),
  );
}

/// Khung dialog chuẩn của ứng dụng.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    required this.actions,
    this.description,
    this.width = 520,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseAccent = accentColor ?? scheme.primary;
    final accent = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(baseAccent, Colors.white, 0.3)!
        : baseAccent;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: screenHeight * 0.86,
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withValues(alpha: 0.16),
                          scheme.surfaceContainer,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(color: accent),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              description!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: child,
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
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
