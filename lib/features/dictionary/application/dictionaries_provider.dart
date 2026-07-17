import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../data/dictionary_repository.dart';

final appPathsProvider = FutureProvider<AppPaths>((ref) => AppPaths.init());

class DictionariesNotifier extends AsyncNotifier<LoadedDictionaries> {
  @override
  Future<LoadedDictionaries> build() async {
    final paths = await ref.watch(appPathsProvider.future);
    // Bộ dict theo ngôn ngữ đang dịch; đổi mode → nạp lại (cache .vydc giữ nhanh).
    final mode = ref.watch(currentModeProvider);
    // Chỉ phụ thuộc dictPaths của mode — đổi thuật toán/tùy chọn khác không reload.
    final dictPaths =
        ref.watch(settingsProvider.select((s) => s.dictPathsFor(mode)));
    final sw = Stopwatch()..start();
    final loaded =
        await DictionaryRepository(paths).loadAll(dictPaths, mode: mode);
    debugPrint('Dictionaries loaded in ${sw.elapsedMilliseconds}ms: '
        '${loaded.stats.entries.map((e) => '${e.key.name} '
            '${e.value.fromCache ? "cache" : "parse"} '
            '${e.value.elapsedMs}ms').join(', ')}');
    return loaded;
  }

  /// Nạp lại toàn bộ (sau khi sửa dict / thêm entry UserDict).
  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final dictionariesProvider =
    AsyncNotifierProvider<DictionariesNotifier, LoadedDictionaries>(
        DictionariesNotifier.new);
