import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dictionary/application/dictionaries_provider.dart';
import '../../features/dictionary/data/user_dict_service.dart';
import '../../features/dictionary_sync/application/dictionary_sync_controller.dart';
import '../../features/dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../features/translation/application/translation_controller.dart';
import 'app_dialog.dart';

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

  final saved = await showAppDialog<bool>(
    context: context,
    icon: toNames ? Icons.badge_outlined : Icons.edit_note,
    accentColor: toNames ? const Color(0xFF00897B) : const Color(0xFFEF6C00),
    title: title ?? (toNames ? 'Thêm vào Names' : 'Sửa nghĩa trong UserDict'),
    description: toNames
        ? 'Tên riêng được ưu tiên khi dịch và chỉ lưu trên máy này.'
        : 'Mục UserDict được ưu tiên cao nhất khi dịch.',
    width: 540,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: keyController,
          decoration: const InputDecoration(labelText: 'Từ nguồn'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: meaningController,
          minLines: 6,
          maxLines: 10,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            labelText: 'Nghĩa',
            helperText: 'Dùng dấu / để ngăn cách nhiều nghĩa.',
          ),
          autofocus: true,
        ),
      ],
    ),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.save_outlined),
        onPressed: () => Navigator.pop(dialogContext, true),
        label: const Text('Lưu từ'),
      ),
    ],
  );

  final key = saved == true ? keyController.text.trim() : '';
  final meaning = saved == true ? meaningController.text.trim() : '';
  keyController.dispose();
  meaningController.dispose();
  if (saved != true) return;
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

/// Dialog sửa trực tiếp VietPhrase/Lạc Việt cục bộ của admin.
/// Mục đã sửa chỉ lên server khi admin bấm Update trong Cài đặt.
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

  final saved = await showAppDialog<bool>(
    context: context,
    icon: Icons.edit_note,
    accentColor: const Color(0xFF00838F),
    title: 'Sửa vào $dictionaryName',
    description:
        'Lưu cục bộ trước; bấm Update trong Cài đặt để gửi lên server.',
    width: 540,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: keyController,
          decoration: const InputDecoration(labelText: 'Từ nguồn'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: meaningController,
          minLines: 6,
          maxLines: 10,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(labelText: 'Nghĩa'),
          autofocus: true,
        ),
      ],
    ),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.save_outlined),
        onPressed: () => Navigator.pop(dialogContext, true),
        label: const Text('Lưu từ'),
      ),
    ],
  );

  final key = saved == true ? keyController.text.trim() : '';
  final meaning = saved == true ? meaningController.text.trim() : '';
  keyController.dispose();
  meaningController.dispose();
  if (saved != true) return;
  if (key.isEmpty || meaning.isEmpty) return;

  try {
    final mode = ref.read(translationControllerProvider).mode;
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEdit(mode: mode, kind: kind, source: key, target: meaning);
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
