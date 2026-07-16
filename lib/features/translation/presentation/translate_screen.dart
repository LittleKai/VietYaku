import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import 'lacviet_panel.dart';
import 'result_pane.dart';
import 'source_pane.dart';

class TranslateScreen extends ConsumerWidget {
  const TranslateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dicts = ref.watch(dictionariesProvider);

    return Column(
      children: [
        if (dicts.isLoading)
          const LinearProgressIndicator(minHeight: 3)
        else if (dicts.hasError)
          MaterialBanner(
            content: Text('Lỗi nạp từ điển: ${dicts.error}'),
            actions: [
              TextButton(
                onPressed: () => ref.invalidate(dictionariesProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        Expanded(
          child: Row(
            children: [
              const Expanded(flex: 3, child: SourcePane()),
              const VerticalDivider(width: 1, thickness: 1),
              const Expanded(flex: 4, child: ResultPane()),
              const VerticalDivider(width: 1, thickness: 1),
              const Expanded(flex: 3, child: LacVietPanel()),
            ],
          ),
        ),
      ],
    );
  }
}
