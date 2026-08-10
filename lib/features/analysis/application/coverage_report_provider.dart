import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../domain/coverage_report.dart';

/// Báo cáo phủ của lượt dịch hiện tại; null khi chưa dịch hoặc dict chưa nạp.
/// Tính lại mỗi khi tokens đổi (dịch lại / thêm mục từ điển rồi reload).
final coverageReportProvider = Provider<CoverageReport?>((ref) {
  final tokens = ref.watch(
    translationControllerProvider.select((s) => s.tokens),
  );
  final mode = ref.watch(translationControllerProvider.select((s) => s.mode));
  final dicts = ref.watch(dictionariesProvider).valueOrNull;
  if (dicts == null || tokens.isEmpty) return null;
  return buildCoverageReport(
    tokens: tokens,
    mode: mode,
    names: dicts.names,
    vietPhrase: dicts.vietPhrase,
  );
});
