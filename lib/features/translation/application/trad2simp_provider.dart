import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trad2simp_table.dart';

final trad2SimpTableProvider = FutureProvider<Trad2SimpTable>((ref) async {
  final tsv = await rootBundle.loadString('assets/mappings/trad2simp.tsv');
  return Trad2SimpTable.parse(tsv);
});

/// Bảng đã nạp xong, hoặc bảng rỗng khi asset chưa về. `translate()` chạy đồng
/// bộ nên không await được; asset chỉ ~20KB và nạp xong trước cả bộ từ điển.
Trad2SimpTable trad2SimpOf(Object ref) {
  final AsyncValue<Trad2SimpTable> asyncVal;
  if (ref is WidgetRef) {
    asyncVal = ref.read(trad2SimpTableProvider);
  } else if (ref is Ref) {
    asyncVal = ref.read(trad2SimpTableProvider);
  } else if (ref is ProviderContainer) {
    asyncVal = ref.read(trad2SimpTableProvider);
  } else {
    return Trad2SimpTable.empty;
  }
  return asyncVal.valueOrNull ?? Trad2SimpTable.empty;
}
