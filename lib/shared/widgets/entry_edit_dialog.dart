// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dictionary/application/dictionaries_provider.dart';
import '../../features/dictionary/data/user_dict_service.dart';
import '../../features/dictionary/domain/entry_impact.dart';
import '../../features/dictionary_search/domain/dictionary_search.dart';
import '../../features/dictionary_sync/application/dictionary_sync_controller.dart';
import '../../features/dictionary_sync/domain/shared_dictionary_entry.dart';
import '../../features/glossary/application/glossary_sync_controller.dart';
import '../../features/glossary/data/glossary_service.dart';
import '../../features/glossary/domain/glossary_term.dart';
import '../../features/glossary/presentation/glossary_update_dialog.dart';
import '../../features/settings/settings_provider.dart';
import '../../features/translation/application/lookup_controller.dart';
import '../../features/translation/application/translation_controller.dart';
import '../../features/translation/domain/reading_extractor.dart';
import '../../features/translation/domain/translation_engine.dart';
import '../../features/translation/domain/vietphrase_value.dart';
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
  String? dictMeaningOf(String key) => dicts == null
      ? null
      : (dicts.userDict.entries[key] ??
            dicts.names.entries[key] ??
            dicts.vietPhrase.entries[key]);
  final existing = initialMeaning ?? dictMeaningOf(word);

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

  final settings = ref.read(settingsProvider);
  final glossaryDir = settings.glossaryDir;
  final glossaryService = GlossaryService(glossaryDir);
  final canUpdateGlossary = glossaryService.hasGlossaryFor(translation.mode);
  holder.autoUpdateGlossaryNotifier.value = settings.autoUpdateGlossaryOnSave;
  holder.notifyOnGlossaryUpdateNotifier.value =
      settings.notifyOnGlossaryAutoUpdate;

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
      hanVietOf: (key) => dicts == null ? null : hanVietReadingOf(dicts, key),
      meaningForKey: dictMeaningOf,
      meaningHelper: 'Dùng dấu / để ngăn cách nhiều nghĩa.',
      mode: translation.mode,
      sourceText: impactSource,
      baseValueOf: baseValueOf,
      currentValueOf: currentValueOf,
      currentLayerLabel: toNames ? 'UserNames hiện tại' : 'UserDict hiện tại',
      glossaryDir: canUpdateGlossary ? glossaryDir : null,
      onAutoUpdateChanged: (val) =>
          ref.read(settingsProvider.notifier).setAutoUpdateGlossaryOnSave(val),
      onNotifyOnUpdateChanged: (val) => ref
          .read(settingsProvider.notifier)
          .setNotifyOnGlossaryAutoUpdate(val),
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
  final autoUpdateGlossary = holder.autoUpdateGlossaryNotifier.value;
  final notifyOnGlossaryUpdate = holder.notifyOnGlossaryUpdateNotifier.value;
  holder.disposeAfterRouteAnimation();
  if (saved != true) return;
  if (key.isEmpty || meaning.isEmpty) return;
  if (key == word.trim() && meaning == (existing ?? '').trim()) return;

  final paths = await ref.read(appPathsProvider.future);
  final service = UserDictService(paths);
  if (toNames) {
    await service.upsertUserName(key, meaning);
  } else {
    await service.upsertUserDict(key, meaning);
  }

  var glossaryAutoUpdated = false;
  String? glossaryNewTarget;
  if (canUpdateGlossary && autoUpdateGlossary) {
    final term = await glossaryService.find(translation.mode, key);
    if (term != null) {
      final target = glossaryTargetOf(meaning);
      if (term.target.trim() != target.trim()) {
        try {
          await glossaryService.upsert(
            translation.mode,
            source: key,
            target: target,
          );
          ref.invalidate(
            glossarySyncRowsProvider(
              GlossarySyncDirection.glossaryToVietPhrase,
            ),
          );
          ref.invalidate(
            glossarySyncRowsProvider(
              GlossarySyncDirection.vietPhraseToGlossary,
            ),
          );
          glossaryAutoUpdated = true;
          glossaryNewTarget = target;
        } catch (_) {}
      }
    }
  }

  await ref.read(dictionariesProvider.notifier).reload();

  // Dịch lại ngay để entry mới áp dụng.
  final latestTranslation = ref.read(translationControllerProvider);
  if (latestTranslation.sourceText.isNotEmpty) {
    ref
        .read(translationControllerProvider.notifier)
        .translate(latestTranslation.sourceText);
  }

  if (glossaryAutoUpdated && notifyOnGlossaryUpdate && context.mounted) {
    final lang = GlossaryService.langFor(translation.mode);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Đã lưu từ điển và tự động cập nhật Global Glossary $lang: $key → $glossaryNewTarget',
          ),
        ),
      );
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
  String? sharedMeaningOf(String key) {
    if (dicts == null) return null;
    if (isVietPhrase) return dicts.vietPhrase.entries[key];
    final lacViet = dicts.lacViet.entries[key];
    if (lacViet != null && lacViet.trim().isNotEmpty) return lacViet;
    final vp = dicts.vietPhrase.entries[key];
    if (vp != null && vp.trim().isNotEmpty) {
      return convertVietPhraseToLacVietFormat(vp);
    }
    return lacViet;
  }

  final existing = sharedMeaningOf(word);
  final holder = _EntryFieldControllers();
  final mode = ref.read(translationControllerProvider).mode;
  final translation = ref.read(translationControllerProvider);
  final sourceText = translation.tokens.isEmpty
      ? translation.sourceText
      : translation.tokens.map((token) => token.source).join();
  final baseLayerId = isVietPhrase ? 'vietPhrase' : 'lacViet';
  final sharedLayerId = isVietPhrase ? 'sharedVietPhrase' : 'sharedLacViet';

  final settings = ref.read(settingsProvider);
  final glossaryDir = settings.glossaryDir;
  final glossaryLang = GlossaryService.langFor(mode);
  final glossaryService = GlossaryService(glossaryDir);
  final canUpdateGlossary =
      isVietPhrase && glossaryService.hasGlossaryFor(mode);
  holder.autoUpdateGlossaryNotifier.value = settings.autoUpdateGlossaryOnSave;
  holder.notifyOnGlossaryUpdateNotifier.value =
      settings.notifyOnGlossaryAutoUpdate;

  final saved = await showAppDialog<String>(
    context: context,
    icon: Icons.edit_note,
    accentColor: const Color(0xFF00838F),
    title: 'Sửa vào $dictionaryName',
    description:
        'Lưu cục bộ trước; bấm Update trong Cài đặt để gửi lên server.',
    width: isVietPhrase ? 760 : 700,
    content: _EntryFields(
      holder: holder,
      initialKey: word,
      initialMeaning: existing ?? '',
      hanVietOf: (key) => dicts == null ? null : hanVietReadingOf(dicts, key),
      meaningForKey: sharedMeaningOf,
      vietPhraseFormat: isVietPhrase,
      lacVietFormat: !isVietPhrase,
      meaningHelper: isVietPhrase
          ? null
          : 'Xuống dòng thật sẽ lưu thành \\n\\t; dấu / tự đổi thành "; ".',
      mode: mode,
      sourceText: sourceText,
      baseValueOf: (key) {
        if (dicts == null) return null;
        final base = _layerValue(dicts.searchLayers, baseLayerId, key);
        if (!isVietPhrase && (base == null || base.isEmpty)) {
          final vpBase = _layerValue(dicts.searchLayers, 'vietPhrase', key);
          if (vpBase != null && vpBase.isNotEmpty) {
            return convertVietPhraseToLacVietFormat(vpBase);
          }
        }
        return base;
      },
      currentValueOf: (key) => dicts == null
          ? null
          : _layerValue(dicts.searchLayers, sharedLayerId, key),
      currentLayerLabel: '$dictionaryName chung hiện tại',
      glossaryDir: isVietPhrase ? glossaryDir : null,
      onAutoUpdateChanged: (val) =>
          ref.read(settingsProvider.notifier).setAutoUpdateGlossaryOnSave(val),
      onNotifyOnUpdateChanged: (val) => ref
          .read(settingsProvider.notifier)
          .setNotifyOnGlossaryAutoUpdate(val),
    ),
    actionsBuilder: (dialogContext) => [
      // Từ nguồn, nghĩa và trạng thái Glossary đều đổi khi người dùng gõ →
      // gộp làm một listenable để nút Glossary/Xóa từ bám theo key hiện tại.
      ListenableBuilder(
        listenable: Listenable.merge([
          holder.glossaryTermNotifier,
          holder.meaningNotifier,
          holder.keyNotifier,
        ]),
        builder: (_, _) {
          final glossaryTerm = holder.glossaryTermNotifier.value;
          final meaningText = holder.meaningNotifier.value;
          final currentKey = holder.keyNotifier.value.trim();
          final existsInGlossary = glossaryTerm != null;
          final currentTarget = glossaryTargetOf(meaningText);
          final isIdenticalGlossary =
              existsInGlossary &&
              glossaryTerm.target.trim() == currentTarget.trim();

          final showGlossaryButton = canUpdateGlossary && !isIdenticalGlossary;
          final canDelete =
              sharedMeaningOf(currentKey) != null || existsInGlossary;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showGlossaryButton)
                TextButton.icon(
                  icon: Icon(
                    existsInGlossary
                        ? Icons.edit_calendar_outlined
                        : Icons.menu_book_outlined,
                    size: 18,
                  ),
                  onPressed: () async {
                    final updated = await showGlossaryUpdateDialog(
                      dialogContext,
                      ref,
                      source: holder.keyText.trim(),
                      meaning: holder.meaningText.trim(),
                    );
                    // Ghi xong thì đọc lại glossary: thẻ trạng thái đổi
                    // sang "ĐÃ CÓ", nút Thêm/Ghi đè tự ẩn khi đã giống hệt.
                    if (updated) holder.refreshGlossary?.call();
                  },
                  label: Text(
                    existsInGlossary
                        ? 'Ghi đè Glossary $glossaryLang'
                        : 'Thêm vào Glossary $glossaryLang',
                  ),
                ),
              if (canDelete)
                TextButton.icon(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, 'delete'),
                  label: const Text(
                    'Xóa từ',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          );
        },
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
    final targetKey = holder.keyText.trim().isNotEmpty
        ? holder.keyText.trim()
        : word;
    final inGlossary =
        canUpdateGlossary &&
        (await glossaryService.find(mode, targetKey)) != null;
    final inSharedDict = sharedMeaningOf(targetKey) != null;

    holder.disposeAfterRouteAnimation();

    if (!context.mounted) return;

    final deleteScope = await _showDeleteConfirmationDialog(
      context: context,
      word: targetKey,
      dictionaryName: dictionaryName,
      glossaryLang: glossaryLang,
      inSharedDict: inSharedDict,
      inGlossary: inGlossary,
    );

    if (deleteScope == null || !context.mounted) return;

    final messages = <String>[];

    if (deleteScope == DeleteScope.vietPhraseOnly ||
        deleteScope == DeleteScope.both) {
      try {
        await ref
            .read(dictionarySyncProvider.notifier)
            .stageLocalDelete(mode: mode, kind: kind, source: targetKey);
        final syncMsg = ref.read(dictionarySyncProvider).message;
        messages.add(syncMsg ?? 'Đã xóa khỏi $dictionaryName chung.');
      } catch (_) {}
    }

    if (deleteScope == DeleteScope.glossaryOnly ||
        deleteScope == DeleteScope.both) {
      try {
        await glossaryService.removeAll(mode, [targetKey]);
        ref.invalidate(
          glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
        );
        ref.invalidate(
          glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
        );
        messages.add('Đã xóa khỏi Global Glossary $glossaryLang.');
      } catch (_) {
        messages.add('Không xóa được khỏi Global Glossary $glossaryLang.');
      }
    }

    if (!context.mounted) return;

    if (messages.isNotEmpty) {
      final text = messages.join('\n');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
    return;
  }

  final key = saved == 'save' ? holder.keyText.trim() : '';
  final meaning = saved == 'save' ? holder.meaningText.trim() : '';
  final autoUpdateGlossary = holder.autoUpdateGlossaryNotifier.value;
  final notifyOnGlossaryUpdate = holder.notifyOnGlossaryUpdateNotifier.value;
  holder.disposeAfterRouteAnimation();
  if (saved != 'save') return;
  if (key.isEmpty || meaning.isEmpty) return;
  if (key == word.trim() && meaning == (existing ?? '').trim()) return;

  try {
    await ref
        .read(dictionarySyncProvider.notifier)
        .stageLocalEdit(mode: mode, kind: kind, source: key, target: meaning);
  } catch (_) {
    // Controller giữ thông báo lỗi đã ánh xạ cho UI.
  }

  var glossaryAutoUpdated = false;
  String? glossaryNewTarget;
  if (canUpdateGlossary && autoUpdateGlossary) {
    final term = await glossaryService.find(mode, key);
    if (term != null) {
      final target = glossaryTargetOf(meaning);
      if (term.target.trim() != target.trim()) {
        try {
          await glossaryService.upsert(mode, source: key, target: target);
          ref.invalidate(
            glossarySyncRowsProvider(
              GlossarySyncDirection.glossaryToVietPhrase,
            ),
          );
          ref.invalidate(
            glossarySyncRowsProvider(
              GlossarySyncDirection.vietPhraseToGlossary,
            ),
          );
          glossaryAutoUpdated = true;
          glossaryNewTarget = target;
        } catch (_) {}
      }
    }
  }

  if (!context.mounted) return;
  final syncMsg = ref.read(dictionarySyncProvider).message;

  if (glossaryAutoUpdated && notifyOnGlossaryUpdate) {
    final baseMsg = syncMsg ?? 'Đã lưu vào $dictionaryName chung.';
    final text =
        '$baseMsg\nĐã tự động cập nhật Global Glossary $glossaryLang: $key → $glossaryNewTarget';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  } else if (syncMsg != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(syncMsg)));
  }
}

enum DeleteScope { vietPhraseOnly, glossaryOnly, both }

Future<DeleteScope?> _showDeleteConfirmationDialog({
  required BuildContext context,
  required String word,
  required String dictionaryName,
  required String glossaryLang,
  required bool inSharedDict,
  required bool inGlossary,
}) async {
  DeleteScope selectedScope = (inSharedDict && inGlossary)
      ? DeleteScope.both
      : (inSharedDict ? DeleteScope.vietPhraseOnly : DeleteScope.glossaryOnly);

  return showAppDialog<DeleteScope>(
    context: context,
    icon: Icons.delete_forever_outlined,
    accentColor: Colors.red,
    title: 'Xác nhận xóa từ "$word"',
    description: 'Chọn phạm vi bạn muốn xóa đối với từ này:',
    width: 520,
    content: StatefulBuilder(
      builder: (context, setState) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (inSharedDict && inGlossary) ...[
              RadioListTile<DeleteScope>(
                value: DeleteScope.both,
                groupValue: selectedScope,
                onChanged: (val) => setState(() => selectedScope = val!),
                activeColor: Colors.red,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  'Xóa cả hai ($dictionaryName & Glossary)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Xóa khỏi cả $dictionaryName chung và Global Glossary $glossaryLang.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
            if (inSharedDict) ...[
              RadioListTile<DeleteScope>(
                value: DeleteScope.vietPhraseOnly,
                groupValue: selectedScope,
                onChanged: (val) => setState(() => selectedScope = val!),
                activeColor: Colors.red,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  inGlossary
                      ? 'Chỉ xóa $dictionaryName'
                      : 'Xóa khỏi $dictionaryName',
                  style: TextStyle(
                    fontWeight: inGlossary
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Xóa khỏi từ điển $dictionaryName chung (xếp hàng chờ Update).',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (inGlossary) const Divider(height: 1),
            ],
            if (inGlossary) ...[
              RadioListTile<DeleteScope>(
                value: DeleteScope.glossaryOnly,
                groupValue: selectedScope,
                onChanged: (val) => setState(() => selectedScope = val!),
                activeColor: Colors.red,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  inSharedDict ? 'Chỉ xóa Glossary' : 'Xóa khỏi Glossary',
                  style: TextStyle(
                    fontWeight: inSharedDict
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Xóa khỏi file Global Glossary $glossaryLang.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, null),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => Navigator.pop(dialogContext, selectedScope),
        label: const Text('Xác nhận xóa'),
      ),
    ],
  );
}

/// Cầu nối đọc text sau khi dialog đóng mà không cần giữ tham chiếu controller.
/// `_EntryFields` cập nhật liên tục để giá trị còn đúng cả sau khi controller
/// đã bị dispose theo vòng đời widget.
class _EntryFieldControllers {
  String keyText = '';
  String meaningText = '';
  final ValueNotifier<bool> canSave = ValueNotifier(false);
  final ValueNotifier<GlossaryTerm?> glossaryTermNotifier = ValueNotifier(null);
  final ValueNotifier<String> meaningNotifier = ValueNotifier('');
  final ValueNotifier<String> keyNotifier = ValueNotifier('');
  final ValueNotifier<bool> autoUpdateGlossaryNotifier = ValueNotifier(true);
  final ValueNotifier<bool> notifyOnGlossaryUpdateNotifier = ValueNotifier(
    true,
  );

  /// Đọc lại mục glossary của key đang gõ. `_EntryFields` gán trong initState;
  /// nút "Thêm/Ghi đè Glossary" (nằm ngoài widget, ở hàng action của dialog)
  /// gọi sau khi ghi file để thẻ trạng thái + nhãn nút cập nhật ngay.
  VoidCallback? refreshGlossary;

  void disposeAfterRouteAnimation() {
    // showDialog hoàn tất Future trước khi reverse animation unmount toàn bộ
    // action; trì hoãn để ValueListenableBuilder không remove listener khỏi
    // notifier đã dispose (cùng vòng đời với controller của _EntryFields).
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      canSave.dispose();
      glossaryTermNotifier.dispose();
      meaningNotifier.dispose();
      keyNotifier.dispose();
      autoUpdateGlossaryNotifier.dispose();
      notifyOnGlossaryUpdateNotifier.dispose();
    });
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
    this.hanVietOf,
    this.meaningForKey,
    this.vietPhraseFormat = false,
    this.lacVietFormat = false,
    this.meaningHelper,
    this.glossaryDir,
    this.onAutoUpdateChanged,
    this.onNotifyOnUpdateChanged,
  });

  final _EntryFieldControllers holder;
  final String initialKey;
  final String initialMeaning;
  final TranslationMode mode;
  final String sourceText;
  final String? Function(String key) baseValueOf;
  final String? Function(String key) currentValueOf;
  final String currentLayerLabel;

  /// Âm Hán Việt của key đang gõ; null (hoặc trả null) thì không hiện dòng này.
  final String? Function(String key)? hanVietOf;

  /// Value thô của key trong từ điển đang sửa. Gõ lại ô Từ nguồn thì ô Nghĩa
  /// nạp lại theo key mới (chỉ khi người dùng chưa tự sửa ô Nghĩa).
  final String? Function(String key)? meaningForKey;

  /// VietPhrase được sửa theo từng nghĩa + từ loại, rồi encode về value một
  /// dòng khi preview/lưu.
  final bool vietPhraseFormat;

  /// Value LacViet nằm gọn 1 dòng với literal `\n`, `\t`: hiển thị bản đã
  /// unescape cho dễ sửa, escape lại (kèm `/` → `; `) trước khi lưu.
  final bool lacVietFormat;
  final String? meaningHelper;
  final String? glossaryDir;
  final ValueChanged<bool>? onAutoUpdateChanged;
  final ValueChanged<bool>? onNotifyOnUpdateChanged;

  @override
  State<_EntryFields> createState() => _EntryFieldsState();
}

class _EntryFieldsState extends State<_EntryFields> {
  late final TextEditingController _keyController;
  TextEditingController? _meaningController;
  final List<_VietPhraseMeaningRowData> _meaningRows = [];
  var _nextMeaningRowId = 0;
  bool _hasInvalidVietPhraseRows = false;

  /// Key mà ô Nghĩa đang hiển thị, cùng value đã encode lúc nạp: lệch nhau
  /// nghĩa là người dùng đã tự sửa → không nạp đè khi đổi Từ nguồn.
  String _meaningSourceKey = '';
  String _loadedMeaning = '';

  /// Chỉ tự focus ô Nghĩa 1 lúc mở dialog; nạp lại theo key mới không được
  /// cướp con trỏ khỏi ô Từ nguồn đang gõ.
  bool _autofocusFirstMeaning = true;
  late EntryImpact _impact;
  String? _hanViet;
  GlossaryTerm? _glossaryTerm;
  bool _isCheckingGlossary = false;
  String? _lastGlossaryKey;
  bool _hasGlossaryFile = false;
  late final String _glossaryLang;

  @override
  void initState() {
    super.initState();
    _glossaryLang = GlossaryService.langFor(widget.mode);
    final dir = widget.glossaryDir;
    if (dir != null && dir.trim().isNotEmpty) {
      _hasGlossaryFile = GlossaryService(dir).hasGlossaryFor(widget.mode);
    }
    _keyController = TextEditingController(text: widget.initialKey)
      ..addListener(_onKeyChanged);
    if (widget.vietPhraseFormat) {
      _meaningRows.addAll(_buildMeaningRows(widget.initialMeaning));
    } else {
      _meaningController = TextEditingController(
        text: widget.lacVietFormat
            ? unescapeLacViet(widget.initialMeaning)
            : widget.initialMeaning,
      )..addListener(_sync);
    }
    _meaningSourceKey = widget.initialKey.trim();
    widget.holder.refreshGlossary = () =>
        _checkGlossaryIfNeeded(_keyController.text.trim(), force: true);
    _sync();
    _loadedMeaning = _encodedMeaning();
  }

  /// Đổi Từ nguồn → nạp lại Nghĩa của key mới trước khi tính lại phần còn lại.
  void _onKeyChanged() {
    _reloadMeaningForKey();
    _sync();
  }

  void _reloadMeaningForKey() {
    final lookup = widget.meaningForKey;
    if (lookup == null) return;
    final key = _keyController.text.trim();
    if (key == _meaningSourceKey) return;
    // Người dùng đã tự sửa ô Nghĩa: giữ nguyên phần đang gõ dở.
    if (_encodedMeaning() != _loadedMeaning) return;

    _meaningSourceKey = key;
    final raw = key.isEmpty ? '' : (lookup(key) ?? '');
    _autofocusFirstMeaning = false;
    if (widget.vietPhraseFormat) {
      final old = List.of(_meaningRows);
      _meaningRows
        ..clear()
        ..addAll(_buildMeaningRows(raw));
      for (final row in old) {
        row.dispose();
      }
    } else {
      _meaningController!.value = TextEditingValue(
        text: widget.lacVietFormat ? unescapeLacViet(raw) : raw,
      );
    }
    _loadedMeaning = _encodedMeaning();
  }

  List<_VietPhraseMeaningRowData> _buildMeaningRows(String raw) {
    final meanings = parseVietPhraseValue(raw);
    if (meanings.isEmpty) {
      return [_newMeaningRow(const VietPhraseMeaning(text: ''))];
    }
    return meanings.map(_newMeaningRow).toList();
  }

  String _encodedMeaning() => widget.vietPhraseFormat
      ? encodeVietPhraseValue(
          _meaningRows.map(
            (row) => VietPhraseMeaning(
              text: row.controller.text,
              partOfSpeech: row.partOfSpeech,
            ),
          ),
        )
      : widget.lacVietFormat
      ? escapeLacVietMeaning(_meaningController!.text)
      : _meaningController!.text;

  void _sync() {
    widget.holder.keyText = _keyController.text;
    widget.holder.keyNotifier.value = _keyController.text;
    final meaning = _encodedMeaning();
    _hasInvalidVietPhraseRows =
        widget.vietPhraseFormat &&
        _meaningRows.any((row) {
          final text = row.controller.text.trim();
          return text.isEmpty || text.contains('\n') || text.contains('\r');
        });
    widget.holder.meaningText = meaning;
    widget.holder.meaningNotifier.value = meaning;
    final key = _keyController.text.trim();
    _hanViet = key.isEmpty ? null : widget.hanVietOf?.call(key);
    _impact = previewEntryImpact(
      rawKey: _keyController.text,
      rawMeaning: meaning,
      sourceText: widget.sourceText,
      mode: widget.mode,
      baseValue: widget.baseValueOf(key),
      currentLayerValue: widget.currentValueOf(key),
    );
    widget.holder.canSave.value = _impact.canSave && !_hasInvalidVietPhraseRows;
    _checkGlossaryIfNeeded(key);
    if (mounted) setState(() {});
  }

  _VietPhraseMeaningRowData _newMeaningRow(VietPhraseMeaning meaning) {
    final row = _VietPhraseMeaningRowData(
      id: _nextMeaningRowId++,
      text: meaning.text,
      partOfSpeech: meaning.partOfSpeech,
    );
    row.controller.addListener(_sync);
    return row;
  }

  void _addMeaning() {
    _meaningRows.add(_newMeaningRow(const VietPhraseMeaning(text: '')));
    _sync();
  }

  void _removeMeaning(_VietPhraseMeaningRowData row) {
    if (_meaningRows.length == 1) return;
    _meaningRows.remove(row);
    row.dispose();
    _sync();
  }

  void _changePartOfSpeech(
    _VietPhraseMeaningRowData row,
    VietPhrasePartOfSpeech? partOfSpeech,
  ) {
    if (partOfSpeech == null) return;
    row.partOfSpeech = partOfSpeech;
    _sync();
  }

  Future<void> _checkGlossaryIfNeeded(String key, {bool force = false}) async {
    final dir = widget.glossaryDir;
    if (dir == null) return;
    if (!force &&
        key == _lastGlossaryKey &&
        (_glossaryTerm != null || _isCheckingGlossary)) {
      return;
    }
    _lastGlossaryKey = key;
    if (!_hasGlossaryFile || key.isEmpty) {
      _glossaryTerm = null;
      _isCheckingGlossary = false;
      widget.holder.glossaryTermNotifier.value = null;
      return;
    }

    _isCheckingGlossary = true;
    final service = GlossaryService(dir);
    final mode = widget.mode;

    try {
      final term = await service.find(mode, key);
      if (!mounted || _keyController.text.trim() != key) return;
      setState(() {
        _glossaryTerm = term;
        _isCheckingGlossary = false;
      });
      widget.holder.glossaryTermNotifier.value = term;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _glossaryTerm = null;
        _isCheckingGlossary = false;
      });
      widget.holder.glossaryTermNotifier.value = null;
    }
  }

  @override
  void dispose() {
    widget.holder.refreshGlossary = null;
    _keyController.dispose();
    _meaningController?.dispose();
    for (final row in _meaningRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _keyController,
          decoration: const InputDecoration(labelText: 'Từ nguồn'),
        ),
        if (_hanViet != null) _HanVietRow(hanViet: _hanViet!),
        const SizedBox(height: 12),
        if (widget.vietPhraseFormat)
          _VietPhraseMeaningEditor(
            rows: _meaningRows,
            hasInvalidRows: _hasInvalidVietPhraseRows,
            autofocusFirst: _autofocusFirstMeaning,
            onAdd: _addMeaning,
            onRemove: _removeMeaning,
            onPartOfSpeechChanged: _changePartOfSpeech,
          )
        else
          TextField(
            controller: _meaningController,
            decoration: InputDecoration(
              labelText: 'Nghĩa',
              helperText: widget.meaningHelper,
              alignLabelWithHint: widget.lacVietFormat,
            ),
            keyboardType: TextInputType.multiline,
            minLines: widget.lacVietFormat ? 3 : 1,
            maxLines: widget.lacVietFormat ? 8 : 5,
            inputFormatters: widget.lacVietFormat
                ? null
                : [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
            autofocus: true,
          ),
        const SizedBox(height: 16),
        if (widget.glossaryDir != null) ...[
          ValueListenableBuilder<bool>(
            valueListenable: widget.holder.autoUpdateGlossaryNotifier,
            builder: (_, autoUpdate, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: widget.holder.notifyOnGlossaryUpdateNotifier,
                builder: (_, notifyOnUpdate, _) {
                  return _GlossaryStatusCard(
                    hasGlossaryFile: _hasGlossaryFile,
                    glossaryLang: _glossaryLang,
                    term: _glossaryTerm,
                    isChecking: _isCheckingGlossary,
                    autoUpdate: autoUpdate,
                    onAutoUpdateChanged: (val) {
                      widget.holder.autoUpdateGlossaryNotifier.value = val;
                      widget.onAutoUpdateChanged?.call(val);
                    },
                    notifyOnUpdate: notifyOnUpdate,
                    onNotifyOnUpdateChanged: (val) {
                      widget.holder.notifyOnGlossaryUpdateNotifier.value = val;
                      widget.onNotifyOnUpdateChanged?.call(val);
                    },
                  );
                },
              );
            },
          ),
        ],
        _EntryImpactPreview(
          impact: _impact,
          currentLayerLabel: widget.currentLayerLabel,
        ),
      ],
    );
  }
}

class _VietPhraseMeaningRowData {
  _VietPhraseMeaningRowData({
    required this.id,
    required String text,
    required this.partOfSpeech,
  }) : controller = TextEditingController(text: text);

  final int id;
  final TextEditingController controller;
  VietPhrasePartOfSpeech partOfSpeech;

  void dispose() => controller.dispose();
}

Color _tierColor(int index, ColorScheme scheme) {
  switch (index % 5) {
    case 0:
      return scheme.primary;
    case 1:
      return const Color(0xFF00897B); // Teal / Emerald
    case 2:
      return const Color(0xFFE65100); // Amber / Deep Orange
    case 3:
      return const Color(0xFF7B1FA2); // Purple / Violet
    case 4:
      return const Color(0xFFC2185B); // Rose
    default:
      return scheme.primary;
  }
}

class _VietPhraseMeaningEditor extends StatelessWidget {
  const _VietPhraseMeaningEditor({
    required this.rows,
    required this.hasInvalidRows,
    required this.autofocusFirst,
    required this.onAdd,
    required this.onRemove,
    required this.onPartOfSpeechChanged,
  });

  final List<_VietPhraseMeaningRowData> rows;
  final bool hasInvalidRows;
  final bool autofocusFirst;
  final VoidCallback onAdd;
  final ValueChanged<_VietPhraseMeaningRowData> onRemove;
  final void Function(
    _VietPhraseMeaningRowData row,
    VietPhrasePartOfSpeech? partOfSpeech,
  )
  onPartOfSpeechChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nextNumber = rows.length + 1;
    final nextColor = _tierColor(rows.length, scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _MeaningRow(
            key: ObjectKey(rows[i]),
            index: i,
            row: rows[i],
            autofocus: autofocusFirst && i == 0,
            canRemove: rows.length > 1,
            onRemove: () => onRemove(rows[i]),
            onPartOfSpeechChanged: (value) =>
                onPartOfSpeechChanged(rows[i], value),
          ),
          if (i + 1 < rows.length) const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('add-vietphrase-meaning'),
            icon: Icon(Icons.add_rounded, size: 18, color: nextColor),
            style: OutlinedButton.styleFrom(
              foregroundColor: nextColor,
              side: BorderSide(color: nextColor.withValues(alpha: 0.5)),
            ),
            onPressed: onAdd,
            label: Text(
              'Thêm nghĩa $nextNumber',
              style: TextStyle(fontWeight: FontWeight.w600, color: nextColor),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: hasInvalidRows
                ? scheme.errorContainer.withValues(alpha: 0.25)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasInvalidRows
                  ? scheme.error.withValues(alpha: 0.4)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasInvalidRows
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: hasInvalidRows ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasInvalidRows
                      ? 'Mỗi tầng nghĩa phải có nội dung và không chứa ký tự xuống dòng.'
                      : 'Dùng dấu / cho các cách dịch trong cùng một tầng. Từ loại mặc định là “Không phân loại”; marker tầng và từ loại sẽ được lưu tự động.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: hasInvalidRows
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MeaningRow extends StatefulWidget {
  const _MeaningRow({
    super.key,
    required this.index,
    required this.row,
    required this.autofocus,
    required this.canRemove,
    required this.onRemove,
    required this.onPartOfSpeechChanged,
  });

  final int index;
  final _VietPhraseMeaningRowData row;
  final bool autofocus;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<VietPhrasePartOfSpeech?> onPartOfSpeechChanged;

  @override
  State<_MeaningRow> createState() => _MeaningRowState();
}

class _MeaningRowState extends State<_MeaningRow> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final number = widget.index + 1;
    final tierColor = _tierColor(widget.index, scheme);
    final isFirst = number == 1;

    return Focus(
      focusNode: _focusNode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isFocused
              ? tierColor.withValues(alpha: 0.12)
              : (isFirst
                  ? scheme.primaryContainer.withValues(alpha: 0.20)
                  : tierColor.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isFocused
                ? tierColor.withValues(alpha: 0.85)
                : (isFirst
                    ? scheme.primary.withValues(alpha: 0.45)
                    : tierColor.withValues(alpha: 0.30)),
            width: _isFocused ? 2.0 : (isFirst ? 1.5 : 1.0),
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: tierColor.withValues(alpha: 0.20),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tierColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: tierColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: ValueKey('vietphrase-meaning-${widget.row.id}'),
                controller: widget.row.controller,
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: 5,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                ],
                decoration: InputDecoration(
                  labelText: number == 1 ? 'Nghĩa' : 'Nghĩa $number',
                  hintText: 'Cách dịch 1/cách dịch 2',
                  alignLabelWithHint: true,
                  labelStyle: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.w600,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: tierColor, width: 2),
                  ),
                ),
                autofocus: widget.autofocus,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<VietPhrasePartOfSpeech>(
                key: ValueKey('vietphrase-pos-${widget.row.id}'),
                initialValue: widget.row.partOfSpeech,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Từ loại',
                  labelStyle: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.w500,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: tierColor, width: 2),
                  ),
                ),
                items: [
                  for (final partOfSpeech in VietPhrasePartOfSpeech.values)
                    DropdownMenuItem(
                      value: partOfSpeech,
                      child: Text(
                        partOfSpeech == VietPhrasePartOfSpeech.none
                            ? partOfSpeech.label
                            : '${partOfSpeech.label} (${partOfSpeech.code})',
                        style: TextStyle(
                          fontWeight: partOfSpeech == VietPhrasePartOfSpeech.none
                              ? FontWeight.normal
                              : FontWeight.w600,
                          color: partOfSpeech == VietPhrasePartOfSpeech.none
                              ? null
                              : tierColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.onPartOfSpeechChanged,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              color: scheme.error,
              tooltip: 'Xóa nghĩa $number',
              onPressed: widget.canRemove ? widget.onRemove : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Âm Hán Việt của từ nguồn (ChinesePhienAmWords), cập nhật theo ô Từ nguồn.
class _HanVietRow extends StatelessWidget {
  const _HanVietRow({required this.hanViet});

  final String hanViet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.translate, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            'Hán Việt: ',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: SelectableText(
              hanViet,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlossaryStatusCard extends StatelessWidget {
  const _GlossaryStatusCard({
    required this.hasGlossaryFile,
    required this.glossaryLang,
    required this.term,
    required this.isChecking,
    required this.autoUpdate,
    required this.onAutoUpdateChanged,
    required this.notifyOnUpdate,
    required this.onNotifyOnUpdateChanged,
  });

  final bool hasGlossaryFile;
  final String glossaryLang;
  final GlossaryTerm? term;
  final bool isChecking;
  final bool autoUpdate;
  final ValueChanged<bool> onAutoUpdateChanged;
  final bool notifyOnUpdate;
  final ValueChanged<bool> onNotifyOnUpdateChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const accentColor = Color(0xFF6A1B9A);

    if (!hasGlossaryFile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 18, color: scheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Glossary $glossaryLang: Chưa trỏ thư mục Glossary trong Cài đặt',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final exists = term != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: exists
            ? accentColor.withValues(alpha: 0.08)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: exists
              ? accentColor.withValues(alpha: 0.4)
              : scheme.outlineVariant,
          width: exists ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                exists
                    ? Icons.check_circle_rounded
                    : Icons.help_outline_rounded,
                size: 20,
                color: exists ? accentColor : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Trạng thái Glossary $glossaryLang',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: exists ? accentColor : scheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: exists
                      ? accentColor
                      : scheme.onSurfaceVariant.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isChecking
                      ? 'Đang kiểm tra...'
                      : (exists
                            ? 'ĐÃ CÓ TRONG GLOSSARY'
                            : 'CHƯA CÓ TRONG GLOSSARY'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: exists ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (!isChecking && exists) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _GlossaryInfoRow(
              label: 'Nghĩa (target)',
              value: term!.target,
              isBold: true,
            ),
            _GlossaryInfoRow(
              label: 'Người tạo (created_by)',
              value: term!.createdBy,
            ),
            if (term!.kind.isNotEmpty)
              _GlossaryInfoRow(label: 'Phân loại (kind)', value: term!.kind),
            if (term!.notes.isNotEmpty)
              _GlossaryInfoRow(label: 'Ghi chú (notes)', value: term!.notes),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => onAutoUpdateChanged(!autoUpdate),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: autoUpdate,
                        onChanged: (val) => onAutoUpdateChanged(val ?? false),
                        activeColor: accentColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tự động cập nhật Glossary $glossaryLang khi bấm "Lưu từ"',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (autoUpdate) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: [
                    Text(
                      'Hiển thị thông báo khi tự động cập nhật',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 24,
                      child: Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          value: notifyOnUpdate,
                          onChanged: onNotifyOnUpdateChanged,
                          activeColor: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (!isChecking && !exists) ...[
            const SizedBox(height: 4),
            Text(
              'Từ này chưa có trong file Global Glossary $glossaryLang.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlossaryInfoRow extends StatelessWidget {
  const _GlossaryInfoRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  final String label;
  final String value;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '${impact.occurrences} lần trong văn bản',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ImpactValue(
            label: 'Giá trị base',
            value: impact.baseValue,
            labelColor: scheme.onSurfaceVariant,
          ),
          _ImpactValue(
            label: currentLayerLabel,
            value: impact.currentLayerValue,
            labelColor: const Color(0xFF0288D1),
            valueColor: const Color(0xFF0288D1),
            isBold: impact.currentLayerValue?.isNotEmpty == true,
          ),
          _ImpactValue(
            label: 'Giá trị mới',
            value: impact.meaning,
            labelColor: const Color(0xFF00897B),
            valueColor: const Color(0xFF00897B),
            isBold: true,
          ),
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
  const _ImpactValue({
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
    this.isBold = false,
  });

  final String label;
  final String? value;
  final Color? labelColor;
  final Color? valueColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: labelColor ?? scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : '—',
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                color: valueColor ?? scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
