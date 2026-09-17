import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../../dictionary_sync/application/dictionary_sync_controller.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/trad2simp_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/translation_engine.dart';
import '../data/dictionary_repository.dart';
import 'language_pack_provider.dart';

final appPathsProvider = FutureProvider<AppPaths>((ref) => AppPaths.init());

class DictionariesNotifier extends AsyncNotifier<LoadedDictionaries> {
  DictionaryBase? _base;
  String? _baseKey;
  bool _reuseBase = false;

  @override
  Future<LoadedDictionaries> build() async {
    // Đọc cờ trước mọi await: rebuild do đổi setting/mode chạy song song thì
    // cũng không được hưởng nhầm.
    final reuseBase = _reuseBase;
    _reuseBase = false;
    final paths = await ref.watch(appPathsProvider.future);
    // Bộ dict theo ngôn ngữ đang dịch; đổi mode → nạp lại (cache .vydc giữ nhanh).
    final mode = ref.watch(currentModeProvider);
    // Mobile: bộ từ điển của mode này phải được chép từ assets ra đĩa trước.
    // Desktop: no-op.
    await ref.watch(languagePackProvider(mode).future);
    // Chỉ phụ thuộc dictPaths của mode — đổi thuật toán/tùy chọn khác không reload.
    final dictPaths = ref.watch(
      settingsProvider.select((s) => s.dictPathsFor(mode)),
    );
    // Bật/tắt merge biến thể Sudachi → nạp lại bộ dict.
    final useSudachiVariants = ref.watch(
      settingsProvider.select((s) => s.sudachiVariants),
    );
    // Mode Trung: quy luôn key phồn thể trong dict về giản thể, cùng công tắc
    // với việc quy văn bản nguồn — tắt thì cả hai phía giữ nguyên phồn thể.
    // Mode Nhật không bao giờ quy (kanji Nhật quy giản thể là phá chữ).
    final convertTrad = ref.watch(
      settingsProvider.select((s) => s.convertTraditionalToSimplified),
    );
    final trad2simp = mode == TranslationMode.chinese && convertTrad
        ? await ref.watch(trad2SimpTableProvider.future)
        : null;
    // Phiên admin ghi AiDict/OnlineDict thẳng vào `data/<lang>/generated` để
    // đóng gói theo bản phát hành → nạp thêm thư mục đó. Người dùng thường chỉ
    // có bản cá nhân trong userdata.
    final isAdmin = ref.watch(
      dictionarySyncProvider.select((s) => s.isAdmin),
    );
    // Mọi thứ quyết định nội dung phần nền; lệch một mục là nạp lại toàn bộ.
    final baseKey = [
      paths.dictionariesDir.path,
      mode.name,
      useSudachiVariants,
      trad2simp?.signature,
      for (final e in dictPaths.entries) '${e.key.name}=${e.value}',
    ].join('\n');
    final base = reuseBase && baseKey == _baseKey ? _base : null;
    final sw = Stopwatch()..start();
    final loaded = await DictionaryRepository(paths).loadAll(
      dictPaths,
      mode: mode,
      useSudachiVariants: useSudachiVariants,
      trad2simp: trad2simp,
      generatedDir: isAdmin ? generatedDictDir(mode) : null,
      base: base,
    );
    _base = loaded.base;
    _baseKey = baseKey;
    debugPrint(
      'Dictionaries ${base == null ? "loaded" : "reloaded overlays"} '
      'in ${sw.elapsedMilliseconds}ms: '
      '${loaded.stats.entries.map((e) => '${e.key.name} '
          '${e.value.fromCache ? "cache" : "parse"} '
          '${e.value.elapsedMs}ms').join(', ')}',
    );
    return loaded;
  }

  /// Nạp lại sau khi sửa/thêm/xóa từ: chỉ đọc lại các file overlay (UserDict,
  /// UserNames, Shared*, AiDict/AiEntries/OnlineDict, VietPhrase overlay), dict
  /// nguồn lớn và nhóm biến thể Sudachi dùng lại bản trong RAM.
  Future<void> reload() async {
    _reuseBase = true;
    ref.invalidateSelf();
    await future;
  }

  /// Nạp lại toàn bộ từ đĩa — dùng khi dict NGUỒN đổi (Repair xuất `*_JP.txt`).
  Future<void> reloadAll() async {
    _reuseBase = false;
    ref.invalidateSelf();
    await future;
  }
}

final dictionariesProvider =
    AsyncNotifierProvider<DictionariesNotifier, LoadedDictionaries>(
      DictionariesNotifier.new,
    );
