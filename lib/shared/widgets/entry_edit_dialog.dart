import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dictionary/application/dictionaries_provider.dart';
import '../../features/dictionary/data/user_dict_service.dart';
import '../../features/dictionary/domain/entry_impact.dart';
import '../../features/dictionary_search/domain/dictionary_search.dart';
import '../../features/dictionary_sync/application/dictionary_sync_controller.dart';
import '../../features/dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../features/glossary/data/glossary_service.dart';
import '../../features/glossary/presentation/glossary_update_dialog.dart';
import '../../features/settings/settings_provider.dart';
import '../../features/translation/application/translation_controller.dart';
import '../../features/translation/domain/translation_engine.dart';
import 'app_dialog.dart';
import 'feature_help_button.dart';

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
  final translation = ref.read(translationControllerProvider);
  final impactSource = translation.tokens.isEmpty
      ? translation.sourceText
      : translation.tokens.map((token) => token.source).join();
  String? baseValueOf(String key) {
    if (dicts == null) return null;
    if (toNames) return _layerValue(dicts.searchLayers, 'names', key);
    return dicts.names.entries[key] ?? dicts.vietPhrase.entries[key];
  }

  String? currentValueOf(String key) => dicts == null
      ? null
      : (toNames
            ? _layerValue(dicts.searchLayers, 'userNames', key)
            : dicts.userDict.entries[key]);

  final saved = await showAppDialog<bool>(
    context: context,
    icon: toNames ? Icons.badge_outlined : Icons.edit_note,
    accentColor: toNames ? const Color(0xFF00897B) : const Color(0xFFEF6C00),
    title: title ?? (toNames ? 'Thêm vào Names' : 'Sửa nghĩa trong UserDict'),
    description: toNames
        ? 'Tên riêng được ưu tiên khi dịch và chỉ lưu trên máy này.'
        : 'Mục UserDict được ưu tiên cao nhất khi dịch.',
    width: 700,
    content: _EntryFields(
      holder: holder,
      initialKey: word,
      initialMeaning: existing ?? '',
      meaningHelper: 'Dùng dấu / để ngăn cách nhiều nghĩa.',
      mode: translation.mode,
      sourceText: impactSource,
      baseValueOf: baseValueOf,
      currentValueOf: currentValueOf,
      currentLayerLabel: toNames ? 'UserNames hiện tại' : 'UserDict hiện tại',
    ),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Hủy'),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: holder.canSave,
        builder: (_, canSave, _) => FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          onPressed: canSave ? () => Navigator.pop(dialogContext, true) : null,
          label: const Text('Lưu từ'),
        ),
      ),
    ],
  );

  // Đọc giá trị ngay khi dialog vừa đóng — controller vẫn sống trong lúc
  // animation thoát; _EntryFields tự dispose khi widget unmount.
  final key = saved == true ? holder.keyText.trim() : '';
  final meaning = saved == true ? holder.meaningText.trim() : '';
  holder.disposeAfterRouteAnimation();
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
  final latestTranslation = ref.read(translationControllerProvider);
  if (latestTranslation.sourceText.isNotEmpty) {
    ref
        .read(translationControllerProvider.notifier)
        .translate(latestTranslation.sourceText);
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
  final mode = ref.read(translationControllerProvider).mode;
  final translation = ref.read(translationControllerProvider);
  final sourceText = translation.tokens.isEmpty
      ? translation.sourceText
      : translation.tokens.map((token) => token.source).join();
  final baseLayerId = isVietPhrase ? 'vietPhrase' : 'lacViet';
  final sharedLayerId = isVietPhrase ? 'sharedVietPhrase' : 'sharedLacViet';

  // Nút đẩy sang glossary chỉ hiện khi thư mục Glossary trong Cài đặt trỏ đúng
  // chỗ (có `<lang>/Global Glossary.json` của ngôn ngữ đang dịch).
  final glossaryLang = GlossaryService.langFor(mode);
  final canUpdateGlossary =
      isVietPhrase &&
      GlossaryService(
        ref.read(settingsProvider).glossaryDir,
      ).hasGlossaryFor(mode);

  final saved = await showAppDialog<String>(
    context: context,
    icon: Icons.edit_note,
    accentColor: const Color(0xFF00838F),
    title: 'Sửa vào $dictionaryName',
    description:
        'Lưu cục bộ trước; bấm Update trong Cài đặt để gửi lên server.',
    width: 700,
    content: _EntryFields(
      holder: holder,
      initialKey: word,
      initialMeaning: existing ?? '',
      mode: mode,
      sourceText: sourceText,
      baseValueOf: (key) => dicts == null
          ? null
          : _layerValue(dicts.searchLayers, baseLayerId, key),
      currentValueOf: (key) => dicts == null
          ? null
          : _layerValue(dicts.searchLayers, sharedLayerId, key),
      currentLayerLabel: '$dictionaryName chung hiện tại',
    ),
    actionsBuilder: (dialogContext) => [
      if (canUpdateGlossary)
        TextButton.icon(
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          onPressed: () => showGlossaryUpdateDialog(
            dialogContext,
            ref,
            source: holder.keyText.trim(),
            meaning: holder.meaningText.trim(),
          ),
          label: Text('Cập nhật Glossary $glossaryLang'),
        ),
      if (existing != null)
        TextButton.icon(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, 'delete'),
          label: const Text(
            'Xóa khỏi chung',
            style: TextStyle(color: Colors.red),
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, 'cancel'),
        child: const Text('Hủy'),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: holder.canSave,
        builder: (_, canSave, _) => FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          onPressed: canSave
              ? () => Navigator.pop(dialogContext, 'save')
              : null,
          label: const Text('Lưu từ'),
        ),
      ),
    ],
  );

  if (saved == 'delete') {
    holder.disposeAfterRouteAnimation();
    try {
      await ref
          .read(dictionarySyncProvider.notifier)
          .stageLocalDelete(mode: mode, kind: kind, source: word);
    } catch (_) {}
    if (!context.mounted) return;
    final message = ref.read(dictionarySyncProvider).message;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    return;
  }

  final key = saved == 'save' ? holder.keyText.trim() : '';
  final meaning = saved == 'save' ? holder.meaningText.trim() : '';
  holder.disposeAfterRouteAnimation();
  if (saved != 'save') return;
  if (key.isEmpty || meaning.isEmpty) return;

  try {
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
  final ValueNotifier<bool> canSave = ValueNotifier(false);

  void disposeAfterRouteAnimation() {
    // showDialog hoàn tất Future trước khi reverse animation unmount toàn bộ
    // action; trì hoãn để ValueListenableBuilder không remove listener khỏi
    // notifier đã dispose (cùng vòng đời với controller của _EntryFields).
    Future<void>.delayed(const Duration(milliseconds: 500), canSave.dispose);
  }
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
    required this.mode,
    required this.sourceText,
    required this.baseValueOf,
    required this.currentValueOf,
    required this.currentLayerLabel,
    this.meaningHelper,
  });

  final _EntryFieldControllers holder;
  final String initialKey;
  final String initialMeaning;
  final TranslationMode mode;
  final String sourceText;
  final String? Function(String key) baseValueOf;
  final String? Function(String key) currentValueOf;
  final String currentLayerLabel;
  final String? meaningHelper;

  @override
  State<_EntryFields> createState() => _EntryFieldsState();
}

class _EntryFieldsState extends State<_EntryFields> {
  late final TextEditingController _keyController;
  late final TextEditingController _meaningController;
  late EntryImpact _impact;

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
    final key = _keyController.text.trim();
    _impact = previewEntryImpact(
      rawKey: _keyController.text,
      rawMeaning: _meaningController.text,
      sourceText: widget.sourceText,
      mode: widget.mode,
      baseValue: widget.baseValueOf(key),
      currentLayerValue: widget.currentValueOf(key),
    );
    widget.holder.canSave.value = _impact.canSave;
    if (mounted) setState(() {});
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
        const SizedBox(height: 16),
        _EntryImpactPreview(
          impact: _impact,
          currentLayerLabel: widget.currentLayerLabel,
        ),
      ],
    );
  }
}

class _EntryImpactPreview extends StatelessWidget {
  const _EntryImpactPreview({
    required this.impact,
    required this.currentLayerLabel,
  });

  final EntryImpact impact;
  final String currentLayerLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.preview_outlined, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Preview tác động',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const FeatureHelpButton(
                title: 'Preview tác động trước khi sửa/publish',
                summary:
                    'Kiểm tra phạm vi ảnh hưởng trước khi thay đổi từ điển cá nhân hoặc từ điển chung.',
                accentColor: Color(0xFF00838F),
                points: [
                  'Giá trị base là nghĩa trong bộ từ điển gốc; lớp hiện tại là UserDict/UserNames hoặc shared overlay đang áp dụng.',
                  'Giá trị mới là nội dung sẽ được ghi; số occurrence cho biết key xuất hiện bao nhiêu lần trong văn bản đang mở.',
                  'Key chứa dấu = hoặc xuống dòng và nghĩa xuống dòng sẽ bị chặn vì có thể làm hỏng format từ điển.',
                  'Cảnh báo khoảng trắng đầu/cuối và script không phù hợp với mode Nhật/Trung giúp phát hiện lỗi nhập liệu.',
                  'Với admin, thay đổi được lưu cục bộ trước và chỉ gửi lên server khi bấm Update.',
                ],
              ),
              const Spacer(),
              Text('${impact.occurrences} lần trong văn bản đang mở'),
            ],
          ),
          const SizedBox(height: 10),
          _ImpactValue(label: 'Giá trị base', value: impact.baseValue),
          _ImpactValue(
            label: currentLayerLabel,
            value: impact.currentLayerValue,
          ),
          _ImpactValue(label: 'Giá trị mới', value: impact.meaning),
          for (final error in impact.errors)
            _ImpactNotice(
              icon: Icons.error_outline,
              color: scheme.error,
              text: error,
            ),
          for (final warning in impact.warnings)
            _ImpactNotice(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFEF6C00),
              text: warning,
            ),
        ],
      ),
    );
  }
}

class _ImpactValue extends StatelessWidget {
  const _ImpactValue({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: Text(value?.isNotEmpty == true ? value! : '—')),
      ],
    ),
  );
}

class _ImpactNotice extends StatelessWidget {
  const _ImpactNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}

String? _layerValue(
  List<DictionarySearchLayer> layers,
  String layerId,
  String key,
) {
  for (final layer in layers) {
    if (layer.id == layerId) return layer.entries[key];
  }
  return null;
}
