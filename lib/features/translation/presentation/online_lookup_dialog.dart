import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../../settings/settings_provider.dart';
import '../application/online_lookup_controller.dart';
import 'lacviet_panel.dart' show meaningLabelColor;

/// Dialog tra online: các nguồn đang bật trong Cài đặt chạy SONG SONG, mỗi
/// nguồn hiện kết quả riêng ngay khi xong (không chờ nguồn kia). Kết quả cũng
/// được chèn vào ô Nghĩa; riêng nguồn từ điển thật (Mazii, Jisho, Weblio) lưu vào
/// `OnlineDict_<mode>.txt`, kết quả máy dịch thì không.
Future<void> showOnlineLookupDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
}) {
  final names = ref
      .read(settingsProvider)
      .onlineLookupSources
      .map((source) => source.label)
      .join(', ');
  return showAppDialog<void>(
    context: context,
    icon: Icons.travel_explore,
    title: 'Tra online: $word',
    description: names.isEmpty
        ? 'Chưa bật nguồn tra online nào trong Cài đặt.'
        : '$names tra song song; nghĩa từ điển thật được lưu vào OnlineDict.',
    accentColor: const Color(0xFF1565C0),
    width: 560,
    content: _OnlineLookupContent(word: word),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Đóng'),
      ),
    ],
  );
}

class _OnlineLookupContent extends ConsumerStatefulWidget {
  const _OnlineLookupContent({required this.word});

  final String word;

  @override
  ConsumerState<_OnlineLookupContent> createState() =>
      _OnlineLookupContentState();
}

class _OnlineLookupContentState extends ConsumerState<_OnlineLookupContent> {
  late final List<OnlineLookupTask> _tasks;

  @override
  void initState() {
    super.initState();
    // Kích hoạt mọi request cùng lúc; phần lưu file chạy độc lập với dialog.
    _tasks = startOnlineLookup(ref, widget.word);
  }

  @override
  Widget build(BuildContext context) {
    if (_tasks.isEmpty) {
      return Text(
        'Bật ít nhất một nguồn trong Cài đặt → Tra online.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _tasks.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          _Section(label: _tasks[i].label, future: _tasks[i].body),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.future});

  final String label;
  final Future<String?> future;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '<<$label>>',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: meaningLabelColor(label, scheme),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        FutureBuilder<String?>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final body = snapshot.data;
            if (body == null || body.trim().isEmpty) {
              return Text(
                'Không có kết quả.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              );
            }
            return SelectableText(body);
          },
        ),
      ],
    );
  }
}
