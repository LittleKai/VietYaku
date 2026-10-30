import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../data/ai_api_client.dart';
import '../data/ai_settings_repository.dart';
import '../domain/ai_service_config.dart';
import '../domain/ai_service_type.dart';

final aiApiClientProvider = Provider<AiApiClient>((ref) => AiApiClient());

final aiSettingsRepositoryProvider = FutureProvider<AiSettingsRepository>((
  ref,
) async {
  final paths = await ref.watch(appPathsProvider.future);
  final prefs = ref.watch(sharedPreferencesProvider);
  return AiSettingsRepository(paths, prefs);
});

class AiSettingsController extends AsyncNotifier<AiSettings> {
  @override
  Future<AiSettings> build() async {
    final repo = await ref.watch(aiSettingsRepositoryProvider.future);
    final settings = await repo.loadSettings();
    return settings;
  }

  Future<void> setActiveService(AiServiceType type) async {
    final current = state.valueOrNull ?? AiSettings.defaults();
    final updated = current.copyWith(activeService: type);
    state = AsyncData(updated);
    final repo = await ref.read(aiSettingsRepositoryProvider.future);
    await repo.saveSettings(updated);
  }

  Future<void> updateServiceConfig(
    AiServiceType type,
    AiServiceConfig config,
  ) async {
    final current = state.valueOrNull ?? AiSettings.defaults();
    final updatedConfigs = Map<AiServiceType, AiServiceConfig>.from(
      current.serviceConfigs,
    );
    updatedConfigs[type] = config;
    final updated = current.copyWith(serviceConfigs: updatedConfigs);
    state = AsyncData(updated);
    final repo = await ref.read(aiSettingsRepositoryProvider.future);
    await repo.saveSettings(updated);
    // Người dùng vừa sửa key/weight → cho các key đang cooldown được thử lại.
    ref.read(aiApiClientProvider).resetFailedKeys();
  }
}

final aiSettingsControllerProvider =
    AsyncNotifierProvider<AiSettingsController, AiSettings>(
      AiSettingsController.new,
    );
