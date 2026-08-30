import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app_paths.dart';
import '../../settings/settings_provider.dart';
import '../../translation/domain/translation_engine.dart';

/// Tiến độ chép bộ từ điển đang chạy (null = không chép gì).
///
/// Tách khỏi [languagePackProvider] vì FutureProvider chỉ có 3 trạng thái
/// loading/data/error — không mang được tiến độ chi tiết.
class LanguagePackProgressNotifier extends Notifier<SeedProgress?> {
  @override
  SeedProgress? build() => null;

  void set(SeedProgress? progress) => state = progress;
}

final languagePackProgressProvider =
    NotifierProvider<LanguagePackProgressNotifier, SeedProgress?>(
      LanguagePackProgressNotifier.new,
    );

/// Đảm bảo bộ từ điển của [mode] đã có trên đĩa.
///
/// Desktop: no-op (từ điển nằm sẵn trong thư mục dự án / cạnh exe).
/// Mobile: chép assets `data/<jp|cn>/**` ra app storage lần đầu, và chép lại
/// khi app lên phiên bản mới (bộ từ điển trong APK có thể đã đổi).
final languagePackProvider = FutureProvider.family<void, TranslationMode>((
  ref,
  mode,
) async {
  if (!AppPaths.needsAssetSeeding) return;
  final info = await PackageInfo.fromPlatform();
  final progress = ref.read(languagePackProgressProvider.notifier);
  try {
    await AppPaths.seedLanguagePack(
      modeDirNames[mode]!,
      signature: '${info.version}+${info.buildNumber}',
      onProgress: progress.set,
    );
  } finally {
    progress.set(null);
  }
});
