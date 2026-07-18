import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_provider.dart';
import '../application/translation_controller.dart';
import 'token_text_view.dart';

/// Tab Hán Việt: phiên âm Hán Việt toàn văn bản nguồn (per chữ Hán).
class HanVietPane extends ConsumerWidget {
  const HanVietPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(
      translationControllerProvider.select((s) => s.hanVietTokens),
    );

    if (tokens.isEmpty) {
      return const Center(
        child: Text('Hán Việt của văn bản nguồn sẽ hiện ở đây'),
      );
    }
    return TokenTextView(
      tokens: tokens,
      textOf: (t) => t.display,
      paneId: PaneId.hanViet,
    );
  }
}
