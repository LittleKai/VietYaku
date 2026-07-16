import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_provider.dart';

/// Danh sách file .txt mở gần đây (tối đa 10, mới nhất trước).
class RecentFilesNotifier extends Notifier<List<String>> {
  static const _key = 'recentFiles';
  static const _max = 10;

  @override
  List<String> build() =>
      ref.watch(sharedPreferencesProvider).getStringList(_key) ?? [];

  Future<void> add(String path) async {
    final list = [path, ...state.where((p) => p != path)];
    if (list.length > _max) list.removeRange(_max, list.length);
    state = list;
    await ref.read(sharedPreferencesProvider).setStringList(_key, list);
  }
}

final recentFilesProvider =
    NotifierProvider<RecentFilesNotifier, List<String>>(
        RecentFilesNotifier.new);
