import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../data/dictionary_search_worker.dart';
import '../domain/dictionary_search.dart';

final dictionarySearchWorkerProvider =
    FutureProvider.autoDispose<DictionarySearchWorker>((ref) async {
      var disposed = false;
      ref.onDispose(() => disposed = true);
      final dictionaries = await ref.watch(dictionariesProvider.future);
      final worker = await DictionarySearchWorker.start(
        dictionaries.searchLayers,
      );
      if (disposed) {
        worker.close();
        throw StateError('Search worker đã hủy');
      }
      ref.onDispose(worker.close);
      return worker;
    });

final dictionarySearchProvider = FutureProvider.autoDispose
    .family<DictionarySearchResponse, DictionarySearchQuery>((
      ref,
      query,
    ) async {
      final worker = await ref.watch(dictionarySearchWorkerProvider.future);
      return worker.search(query);
    });
