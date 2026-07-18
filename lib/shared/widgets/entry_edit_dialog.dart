import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dictionary/application/dictionaries_provider.dart';
import '../../features/dictionary/data/user_dict_service.dart';
import '../../features/dictionary_sync/application/dictionary_sync_controller.dart';
import '../../features/dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../features/translation/application/translation_controller.dart';

/// Dialog sửa nghĩa / thêm entry vào UserDict (hoặc UserNames overlay).
/// Lưu xong: reload từ điển + dịch lại văn bản hiện tại ngay.
Future<void> showEntryEditDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
  required bool toNames,
  String? title,
  String? initialMeaning,
}) async {
  final dicts = ref.read(dictionariesProvider).valueOrNull;
  final existing =
      initialMeaning ??
      (dicts == null
          ? null
          : (dicts.userDict.entries[word] ??
                dicts.names.entries[word] ??
                dicts.vietPhrase.entries[word]));

  final keyController = TextEditingController(text: word);
  final meaningController = TextEditingController(text: existing ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        title ?? (toNames ? 'Thêm vào Names' : 'Sửa nghĩa (UserDict)'),
      ),
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
                labelText: 'Nghĩa (nhiều nghĩa ngăn bằng /)',
              ),
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

/// Dialog cập nhật VietPhrase/Lạc Việt chung, chỉ gọi khi đã đăng nhập admin.
Future<void> showSharedEntryEditDialog(
  BuildContext context,
  WidgetRef ref, {
  required String word,
  required SharedDictionaryKind kind,
}) async {
  final isVietPhrase = kind == SharedDictionaryKind.vietPhrase;
  final dictionaryName = isVietPhrase ? 'VietPhrase' : 'Lạc Việt';
  final dicts = ref.read(dictionariesProvider).valueOrNull;
  final existing = dicts == null
      ? null
      : (isVietPhrase
            ? dicts.vietPhrase.entries[word]
            : dicts.lacViet.entries[word]);
  final keyController = TextEditingController(text: word);
  final meaningController = TextEditingController(text: existing ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Cập nhật $dictionaryName chung'),
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
              decoration: const InputDecoration(labelText: 'Nghĩa'),
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
          child: const Text('Cập nhật'),
        ),
      ],
    ),
  );

  if (saved != true) return;
  final key = keyController.text.trim();
  final meaning = meaningController.text.trim();
  if (key.isEmpty || meaning.isEmpty) return;

  try {
    final mode = ref.read(translationControllerProvider).mode;
    await ref
        .read(dictionarySyncProvider.notifier)
        .publish(mode: mode, kind: kind, source: key, target: meaning);
  } catch (_) {
    // Controller giữ thông báo lỗi đã ánh xạ cho UI.
  }
  if (!context.mounted) return;
  final message = ref.read(dictionarySyncProvider).message;
  if (message != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
