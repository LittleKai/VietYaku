import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../application/lookup_controller.dart';
import '../application/translation_controller.dart';
import '../domain/translation_engine.dart';
import 'lacviet_panel.dart' show meaningLabelColor;

/// Dialog tra online: Mazii và Google Dịch chạy SONG SONG, mỗi nguồn hiện
/// kết quả riêng ngay khi xong (không chờ nguồn kia).
Future<void> showOnlineLookupDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
}) {
  final maziiName =
      ref.read(currentModeProvider) == TranslationMode.japanese
      ? 'Mazii'
      : 'Mazii Trung-Việt';
  return showAppDialog<void>(
    context: context,
    icon: Icons.travel_explore,
    title: 'Tra online: $word',
    description: '$maziiName và Google Dịch tra song song.',
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
  late final Future<String?> _mazii;
  late final Future<String?> _google;
  late final String _maziiLabel;

  @override
  void initState() {
    super.initState();
    final word = widget.word;
    final isJa = ref.read(currentModeProvider) == TranslationMode.japanese;
    // Nhật → Mazii Nhật-Việt (javi); Trung → Mazii Trung-Việt (cnvi).
    _maziiLabel = isJa ? 'Mazii' : 'Mazii Trung-Việt';
    // Kích hoạt hai request cùng lúc.
    _mazii = ref
        .read(maziiApiProvider)
        .lookup(word, dict: isJa ? 'javi' : 'cnvi');
    _google = ref
        .read(googleTranslateProvider)
        .translate(word, sourceLang: isJa ? 'ja' : 'zh-CN');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(label: _maziiLabel, future: _mazii),
        const SizedBox(height: 20),
        _Section(label: 'Google Dịch', future: _google),
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
