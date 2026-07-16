import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dictionary/application/dictionaries_provider.dart';
import '../dictionary/data/dictionary_repository.dart';
import '../dictionary/domain/dict_type.dart';
import '../translation/domain/translation_engine.dart';
import 'settings_provider.dart';

const _dictLabels = <DictType, String>{
  DictType.vietPhrase: 'VietPhrase.txt',
  DictType.lacViet: 'LacViet.txt',
  DictType.names: 'Names.txt',
  DictType.chinesePhienAm: 'ChinesePhienAmWords.txt',
  DictType.pronouns: 'Pronouns.txt',
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pickPath(WidgetRef ref, DictType type) async {
    const typeGroup = XTypeGroup(label: 'Text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await ref.read(settingsProvider.notifier).setDictPath(type, file.path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final dicts = ref.watch(dictionariesProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Chế độ dịch mặc định',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<TranslationMode>(
            segments: const [
              ButtonSegment(
                  value: TranslationMode.japanese, label: Text('Nhật')),
              ButtonSegment(
                  value: TranslationMode.chinese, label: Text('Trung')),
            ],
            selected: {settings.defaultMode},
            onSelectionChanged: (selection) => ref
                .read(settingsProvider.notifier)
                .setDefaultMode(selection.first),
          ),
        ),
        const SizedBox(height: 24),
        Text('Đường dẫn file từ điển',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'File đã sửa (*_JP.txt trong dữ liệu app) tự động được ưu tiên '
          'hơn file gốc.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final entry in _dictLabels.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Text(entry.value),
                if (dicts != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${_entryCount(dicts, entry.key)} entries)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            subtitle: Text(settings.dictPaths[entry.key] ?? '',
                overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Chọn file khác',
              onPressed: () => _pickPath(ref, entry.key),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.refresh),
            label: const Text('Nạp lại từ điển'),
            onPressed: () =>
                ref.read(dictionariesProvider.notifier).reload(),
          ),
        ),
      ],
    );
  }

  static int _entryCount(LoadedDictionaries dicts, DictType type) {
    switch (type) {
      case DictType.vietPhrase:
        return dicts.vietPhrase.length;
      case DictType.lacViet:
        return dicts.lacViet.length;
      case DictType.names:
        return dicts.names.length;
      case DictType.chinesePhienAm:
        return dicts.chinesePhienAm.length;
      case DictType.pronouns:
        return dicts.pronouns.length;
      case DictType.userDict:
        return dicts.userDict.length;
    }
  }
}
