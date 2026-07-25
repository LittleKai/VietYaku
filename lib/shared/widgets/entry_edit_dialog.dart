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

  final holder = _EntryFieldControllers();

  final saved = await showAppDialog<bool>(
    context: context,
    icon: toNames ? Icons.badge_outlined : Icons.edit_note,
    accentColor: toNames ? const Color(0xFF00897B) : const Color(0xFFEF6C00),
    title: title ?? (toNames ? 'Thêm vào Names' : 'Sửa nghĩa trong UserDict'),
    description: toNames
        ? 'Tên riêng được ưu tiên khi dịch và chỉ lưu trên máy này.'
        : 'Mục UserDict được ưu tiên cao nhất khi dịch.',
    width: 540,
    content: _EntryFields(
      holder: holder,
      initialKey: word,
      initialMeaning: existing ?? '',
      meaningHelper: 'Dùng dấu / để ngăn cách nhiều nghĩa.',
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

  // Đọc giá trị ngay khi dialog vừa đóng — controller vẫn sống trong lúc
  // animation thoát; _EntryFields tự dispose khi widget unmount.
  final key = saved == true ? holder.keyText.trim() : '';
  final meaning = saved == true ? holder.meaningText.trim() : '';
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
  final holder = _EntryFieldControllers();

  final saved = await showAppDialog<bool>(
    context: context,
    icon: Icons.edit_note,
    accentColor: const Color(0xFF00838F),
    title: 'Sửa vào $dictionaryName',
    description:
        'Lưu cục bộ trước; bấm Update trong Cài đặt để gửi lên server.',
    width: 540,
    content: _EntryFields(
      holder: holder,
      initialKey: word,
      initialMeaning: existing ?? '',
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

  final key = saved == true ? holder.keyText.trim() : '';
  final meaning = saved == true ? holder.meaningText.trim() : '';
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

/// Cầu nối đọc text sau khi dialog đóng mà không cần giữ tham chiếu controller.
/// `_EntryFields` cập nhật liên tục để giá trị còn đúng cả sau khi controller
/// đã bị dispose theo vòng đời widget.
class _EntryFieldControllers {
  String keyText = '';
  String meaningText = '';
}

/// Nội dung dialog sửa entry: sở hữu và dispose controller theo vòng đời widget
/// (dispose chạy khi element unmount — SAU khi animation thoát kết thúc), tránh
/// crash "used after being disposed" khi TextField rebuild trong lúc dialog
/// đang animate đóng.
class _EntryFields extends StatefulWidget {
  const _EntryFields({
    required this.holder,
    required this.initialKey,
    required this.initialMeaning,
    this.meaningHelper,
  });

  final _EntryFieldControllers holder;
  final String initialKey;
  final String initialMeaning;
  final String? meaningHelper;

  @override
  State<_EntryFields> createState() => _EntryFieldsState();
}

class _EntryFieldsState extends State<_EntryFields> {
  late final TextEditingController _keyController;
  late final TextEditingController _meaningController;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initialKey)
      ..addListener(_sync);
    _meaningController = TextEditingController(text: widget.initialMeaning)
      ..addListener(_sync);
    _sync();
  }

  void _sync() {
    widget.holder.keyText = _keyController.text;
    widget.holder.meaningText = _meaningController.text;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _meaningController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _keyController,
          decoration: const InputDecoration(labelText: 'Từ nguồn'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _meaningController,
          minLines: 6,
          maxLines: 10,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            labelText: 'Nghĩa',
            helperText: widget.meaningHelper,
          ),
          autofocus: true,
        ),
      ],
    );
  }
}
