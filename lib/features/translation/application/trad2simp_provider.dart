import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trad2simp_table.dart';

final trad2SimpTableProvider = FutureProvider<Trad2SimpTable>((ref) async {
  final tsv = await rootBundle.loadString('assets/mappings/trad2simp.tsv');
  return Trad2SimpTable.parse(tsv);
});

/// Bảng đã nạp xong, hoặc bảng rỗng khi asset chưa về. `translate()` chạy đồng
/// bộ nên không await được; asset chỉ ~20KB và nạp xong trước cả bộ từ điển.
Trad2SimpTable trad2SimpOf(Ref ref) =>
    ref.read(trad2SimpTableProvider).valueOrNull ?? Trad2SimpTable.empty;
