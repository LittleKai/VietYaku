import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_provider.dart';
import '../data/user_glossary_service.dart';

/// `UserGlossaryService` đọc/ghi `User Glossary.json` của AI_Translation_Bridge
/// trong thư mục cấu hình `settingsProvider.glossaryDir`.
final userGlossaryServiceProvider = Provider<UserGlossaryService>((ref) {
  final dir = ref.watch(settingsProvider.select((s) => s.glossaryDir));
  return UserGlossaryService(dir);
});
