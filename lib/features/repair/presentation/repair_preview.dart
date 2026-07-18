import 'package:flutter/material.dart';

/// Bảng preview before/after (tối đa 50 dòng thay đổi đầu tiên).
class RepairPreview extends StatelessWidget {
  final List<(String, String)> pairs;

  const RepairPreview({super.key, required this.pairs});

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) {
      return const Center(
        child: Text('Không có dòng nào thay đổi với policy hiện tại'),
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: pairs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final (before, after) = pairs[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                before,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: theme.colorScheme.error.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              Text(
                after,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ],
          ),
        );
      },
    );
  }
}
