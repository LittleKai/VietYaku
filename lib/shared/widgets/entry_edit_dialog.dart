import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dictionary/application/dictionaries_provider.dart';
import '../../features/dictionary/data/user_dict_service.dart';
import '../../features/translation/application/translation_controller.dart';

/// Dialog sửa nghĩa / thêm entry vào UserDict (hoặc UserNames overlay).
/// Lưu xong: reload từ điển + dịch lại văn bản hiện tại ngay.
Future<void> showEntryEditDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
  required bool toNames,
}) async {
  final dicts = ref.read(dictionariesProvider).valueOrNull;
  final existing = dicts == null
      ? null
      : (dicts.userDict.entries[word] ??
          dicts.names.entries[word] ??
          dicts.vietPhrase.entries[word]);

  final keyController = TextEditingController(text: word);
  final meaningController = TextEditingController(text: existing ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(toNames ? 'Thêm vào Names' : 'Sửa nghĩa (UserDict)'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'Từ (key)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: meaningController,
              decoration: const InputDecoration(
                  labelText: 'Nghĩa (nhiều nghĩa ngăn bằng /)'),
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );

  if (saved != true) return;
  final key = keyController.text.trim();
  final meaning = meaningController.text.trim();
  if (key.isEmpty || meaning.isEmpty) return;

  final paths = await ref.read(appPathsProvider.future);
  final service = UserDictService(paths);
  if (toNames) {
    await service.upsertUserName(key, meaning);
  } else {
    await service.upsertUserDict(key, meaning);
  }
  await ref.read(dictionariesProvider.notifier).reload();

  // Dịch lại ngay để entry mới áp dụng.
  final translation = ref.read(translationControllerProvider);
  if (translation.sourceText.isNotEmpty) {
    ref
        .read(translationControllerProvider.notifier)
        .translate(translation.sourceText);
  }
}
