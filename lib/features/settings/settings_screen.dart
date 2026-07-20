import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/tts_service.dart';
import '../../shared/widgets/settings_layout.dart';
import '../dictionary/application/dictionaries_provider.dart';
import '../dictionary_sync/application/dictionary_sync_controller.dart';
import '../repair/domain/jp_repair_pipeline.dart';
import '../repair/presentation/repair_screen.dart';
import '../translation/application/translation_controller.dart';
import '../translation/domain/translation_engine.dart';
import '../translation/domain/lookup_dictionary_type.dart';
import '../update/application/update_controller.dart';
import '../update/presentation/update_dialog.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsPage(
      title: 'Cài đặt',
      description:
          'Cấu hình cách dịch, phát âm, sửa và đồng bộ dữ liệu từ điển.',
      children: [
        SettingsSection(
          icon: Icons.account_tree_outlined,
          accentColor: const Color(0xFF3949AB),
          title: 'Xử lý bản dịch',
          description: 'Các thay đổi được áp dụng ở lần bấm Dịch tiếp theo.',
          children: [
            SettingsControlRow(
              title: 'Thuật toán dịch',
              description: 'Chọn cách ưu tiên cụm từ khi quét toàn bộ văn bản.',
              controlWidth: 500,
              control: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<TranslationAlgorithm>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: TranslationAlgorithm.leftToRight,
                      label: Text('Trái → phải'),
                      tooltip:
                          'Quét trái sang phải, mỗi vị trí lấy cụm dài nhất',
                    ),
                    ButtonSegment(
                      value: TranslationAlgorithm.longestPhrase,
                      label: Text('Ưu tiên cụm dài'),
                      tooltip: 'Cụm dài nhất toàn văn bản được dịch trước',
                    ),
                    ButtonSegment(
                      value: TranslationAlgorithm.longestPhrase4,
                      label: Text('Cụm dài ≥ 4'),
                      tooltip:
                          'Chỉ cụm từ 4 ký tự trở lên được ưu tiên toàn văn',
                    ),
                  ],
                  selected: {settings.translationAlgorithm},
                  onSelectionChanged: (selection) =>
                      notifier.setTranslationAlgorithm(selection.first),
                ),
              ),
            ),
            SettingsSwitchRow(
              title: 'Ưu tiên Names hơn VietPhrase',
              description:
                  'Names tại một vị trí thắng cụm VietPhrase dài hơn. UserDict vẫn cao nhất.',
              value: settings.prioritizeNames,
              onChanged: notifier.setPrioritizeNames,
            ),
            SettingsSwitchRow(
              title: 'Chuẩn hoá Katakana nửa hình',
              description:
                  'Mode Nhật: đổi ｱｲｳ và ｶﾞ thành アイウ và ガ trước khi tra từ điển.',
              value: settings.normalizeHalfwidthKana,
              onChanged: notifier.setNormalizeHalfwidthKana,
            ),
            SettingsSwitchRow(
              title: 'Gộp số Kanji thành số Ả Rập',
              description:
                  'Mode Nhật: đổi run số chưa match như 三百二十五 thành 325; cụm đã match giữ nguyên.',
              value: settings.joinKanjiNumerals,
              onChanged: notifier.setJoinKanjiNumerals,
            ),
            SettingsSwitchRow(
              title: 'Dùng từ điển biến thể Sudachi',
              description:
                  'Mode Nhật: tra biến thể Okurigana như 打込む → 打ち込む. Đổi lựa chọn sẽ nạp lại từ điển.',
              value: settings.sudachiVariants,
              onChanged: notifier.setSudachiVariants,
            ),
            SettingsControlRow(
              title: 'Nguồn phát âm Kana',
              description:
                  'Mode Nhật: chọn thứ tự ưu tiên phát âm trong ô Nghĩa.',
              controlWidth: 430,
              control: DropdownMenu<SudachiReadingsMode>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: settings.sudachiReadings,
                onSelected: (value) {
                  if (value != null) notifier.setSudachiReadings(value);
                },
                dropdownMenuEntries: const [
                  DropdownMenuEntry(
                    value: SudachiReadingsMode.sudachiFirst,
                    label: 'Ưu tiên SudachiDict',
                  ),
                  DropdownMenuEntry(
                    value: SudachiReadingsMode.jaViFirst,
                    label: 'Ưu tiên Nhật Việt / Lạc Việt',
                  ),
                  DropdownMenuEntry(
                    value: SudachiReadingsMode.disabled,
                    label: 'Không dùng SudachiDict',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SettingsSection(
          icon: Icons.open_in_new_outlined,
          accentColor: Color(0xFF7B1FA2),
          title: 'Popup tra nhanh',
          description:
              'Hiện nghĩa khi active một cụm trong ô Nguồn; chọn tối đa 2 từ điển.',
          children: [_PopupDictionarySetting()],
        ),
        const SettingsSection(
          icon: Icons.volume_up_outlined,
          accentColor: Color(0xFF00897B),
          title: 'Phát âm',
          description: 'Giọng đọc và tốc độ riêng cho tiếng Nhật, tiếng Trung.',
          children: [
            _TtsSpeedSetting(),
            _TtsVoiceSetting(mode: TranslationMode.japanese),
            _TtsVoiceSetting(mode: TranslationMode.chinese),
          ],
        ),
        if (!Platform.isAndroid)
          SettingsSection(
            icon: Icons.handyman_outlined,
            accentColor: const Color(0xFFEF6C00),
            title: 'Sửa từ điển',
            description:
                'Sửa key thuần Hán, xuất file _JP.txt và nạp kết quả vào ứng dụng.',
            children: [
              SettingsControlRow(
                title: 'Chính sách key thuần Hán',
                description:
                    'Quyết định cách xử lý biến thể khi chạy công cụ sửa từ điển.',
                controlWidth: 500,
                control: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<RepairPolicy>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: RepairPolicy.addVariant,
                        label: Text('Giữ gốc + thêm JP'),
                      ),
                      ButtonSegment(
                        value: RepairPolicy.convert,
                        label: Text('Convert hết'),
                      ),
                      ButtonSegment(
                        value: RepairPolicy.keepOnly,
                        label: Text('Không convert'),
                      ),
                    ],
                    selected: {settings.repairPolicy},
                    onSelectionChanged: (selection) =>
                        notifier.setRepairPolicy(selection.first),
                  ),
                ),
              ),
              const RepairScreen(showHeader: false),
            ],
          ),
        const SettingsSection(
          icon: Icons.cloud_sync_outlined,
          accentColor: Color(0xFF00838F),
          title: 'Từ điển chung',
          description:
              'Kéo bản mới từ server; tự động đồng bộ hoặc cập nhật thủ công. Đăng nhập quản trị để xuất bản thay đổi.',
          children: [_DictionarySyncSettings()],
        ),
        SettingsSection(
          icon: Icons.menu_book_outlined,
          accentColor: const Color(0xFFC62828),
          title: 'Dữ liệu từ điển',
          description:
              'Mỗi ngôn ngữ dùng một bộ riêng; bản _JP.txt đã sửa được ưu tiên cho tiếng Nhật.',
          children: [
            SettingsControlRow(
              title: 'Nạp lại từ điển',
              description:
                  'Đọc lại dữ liệu trên đĩa và cập nhật bộ dịch đang dùng.',
              controlWidth: 210,
              control: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Nạp lại dữ liệu'),
                  onPressed: () =>
                      ref.read(dictionariesProvider.notifier).reload(),
                ),
              ),
            ),
          ],
        ),
        const SettingsSection(
          icon: Icons.system_update_alt_outlined,
          accentColor: Color(0xFF0277BD),
          title: 'Cập nhật ứng dụng',
          description: 'Kiểm tra và tải bản mới từ GitHub Releases.',
          children: [_UpdateSettings()],
        ),
      ],
    );
  }
}

class _PopupDictionarySetting extends ConsumerWidget {
  const _PopupDictionarySetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      settingsProvider.select((settings) => settings.popupDictionaryTypes),
    );
    final atLimit = selected.length >= 2;
    return SettingsControlRow(
      title: 'Từ điển trong popup',
      description:
          'Mặc định là Lạc Việt. Bỏ chọn tất cả để tắt popup hoàn toàn.',
      controlWidth: 540,
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          for (final type in LookupDictionaryType.values)
            FilterChip(
              label: Text(type.label),
              selected: selected.contains(type),
              onSelected: !selected.contains(type) && atLimit
                  ? null
                  : (enabled) {
                      final next = [...selected];
                      enabled ? next.add(type) : next.remove(type);
                      ref
                          .read(settingsProvider.notifier)
                          .setPopupDictionaryTypes(next);
                    },
            ),
        ],
      ),
    );
  }
}

class _TtsSpeedSetting extends ConsumerWidget {
  const _TtsSpeedSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(
      settingsProvider.select((value) => value.ttsSpeechRate),
    );
    final notifier = ref.read(settingsProvider.notifier);
    final ratePct = (rate * 100).round();

    return SettingsControlRow(
      title: 'Tốc độ đọc',
      description: 'Áp dụng cho cả giọng Nhật và Trung.',
      controlWidth: 430,
      control: Row(
        children: [
          Expanded(
            child: Slider(
              value: rate,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              label: '$ratePct%',
              onChanged: notifier.setTtsSpeechRate,
            ),
          ),
          SizedBox(
            width: 54,
            child: Text('$ratePct%', textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _TtsVoiceSetting extends ConsumerWidget {
  const _TtsVoiceSetting({required this.mode});

  final TranslationMode mode;

  static const _samples = <TranslationMode, String>{
    TranslationMode.japanese: 'こんにちは',
    TranslationMode.chinese: '你好',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tts = ref.watch(ttsServiceProvider).valueOrNull;
    final label = mode == TranslationMode.japanese
        ? 'Tiếng Nhật'
        : 'Tiếng Trung';
    final voices = tts?.voicesFor(mode) ?? const <Map<String, String>>[];
    final available = tts?.availableFor(mode) ?? false;

    if (!available || voices.isEmpty) {
      return SettingsControlRow(
        title: 'Giọng $label',
        description: 'Chưa có giọng ${TtsService.languageFor(mode)} trên máy.',
        controlWidth: 220,
        control: Text(
          'Không khả dụng',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final current = settings.ttsVoiceFor(mode);
    final entries = <DropdownMenuEntry<String>>[
      const DropdownMenuEntry(value: '', label: 'Tự động'),
      for (final voice in voices)
        DropdownMenuEntry(
          value: TtsService.voiceKeyOf(voice),
          label: voice['name'] ?? '',
        ),
    ];
    final initial = entries.any((entry) => entry.value == current)
        ? current
        : '';

    return SettingsControlRow(
      title: 'Giọng $label',
      description: 'Chọn giọng hệ thống hoặc để ứng dụng tự động chọn.',
      controlWidth: 430,
      control: Row(
        children: [
          Expanded(
            child: DropdownMenu<String>(
              key: ValueKey('tts:${mode.name}:$initial'),
              initialSelection: initial,
              expandedInsets: EdgeInsets.zero,
              onSelected: (value) => ref
                  .read(settingsProvider.notifier)
                  .setTtsVoice(mode, value ?? ''),
              dropdownMenuEntries: entries,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.volume_up),
            tooltip: 'Nghe thử $label',
            onPressed: () => tts!.speak(
              _samples[mode]!,
              mode,
              voiceKey: settings.ttsVoiceFor(mode),
              rate: settings.ttsSpeechRate,
            ),
          ),
        ],
      ),
    );
  }
}

class _DictionarySyncSettings extends ConsumerStatefulWidget {
  const _DictionarySyncSettings();

  @override
  ConsumerState<_DictionarySyncSettings> createState() =>
      _DictionarySyncSettingsState();
}

class _DictionarySyncSettingsState
    extends ConsumerState<_DictionarySyncSettings> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final url = ref.read(settingsProvider).syncServerUrl;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showMessage('Hãy nhập tài khoản và mật khẩu.');
      return;
    }

    try {
      await ref
          .read(dictionarySyncProvider.notifier)
          .login(serverUrl: url, username: username, password: password);
      _passwordController.clear();
      _showMessage('Đã đăng nhập quản trị.');
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        ref.read(dictionarySyncProvider).message ?? 'Không thể đăng nhập.',
      );
    }
  }

  Future<void> _publishPending() async {
    try {
      await ref.read(dictionarySyncProvider.notifier).publishPending();
    } catch (_) {
      // Controller đã ánh xạ lỗi kỹ thuật sang thông báo UI.
    }
    if (!mounted) return;
    _showMessage(
      ref.read(dictionarySyncProvider).message ?? 'Không thể Update server.',
    );
  }

  Future<void> _syncNow() async {
    final mode = ref.read(translationControllerProvider).mode;
    try {
      await ref.read(dictionarySyncProvider.notifier).sync(mode);
    } catch (_) {
      // Controller đã ánh xạ lỗi kỹ thuật sang thông báo UI.
    }
    if (!mounted) return;
    _showMessage(
      ref.read(dictionarySyncProvider).message ?? 'Không thể cập nhật từ điển.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(dictionarySyncProvider);
    final session = sync.session;
    final autoSync = ref.watch(
      settingsProvider.select((s) => s.autoSyncDictionary),
    );

    return Column(
      children: [
        SettingsSwitchRow(
          title: 'Tự động đồng bộ khi mở app',
          description:
              'Kéo bản từ điển chung mới nhất từ server mỗi lần khởi động. Mặc định tắt.',
          value: autoSync,
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAutoSyncDictionary(value),
        ),
        SettingsControlRow(
          title: 'Cập nhật từ điển',
          description:
              'Kéo thủ công bản mới nhất của ngôn ngữ đang chọn từ server.',
          controlWidth: 210,
          control: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: sync.isSyncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('Cập nhật từ điển'),
              onPressed: sync.isSyncing ? null : _syncNow,
            ),
          ),
        ),
        SettingsControlRow(
          title: 'Tài khoản quản trị',
          description: sync.isAdmin
              ? 'Phiên được lưu trên máy. Sửa cục bộ trước, chỉ gửi lên server khi bấm Update.'
              : 'Chỉ cần đăng nhập khi muốn xuất bản thay đổi chung.',
          controlWidth: 650,
          control: session != null
              ? Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(session.username),
                    FilledButton.tonalIcon(
                      icon: sync.isPublishing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Update'),
                      onPressed: sync.isPublishing ? null : _publishPending,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Đăng xuất'),
                      onPressed: () =>
                          ref.read(dictionarySyncProvider.notifier).logout(),
                    ),
                  ],
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: _usernameController,
                        enabled: !sync.isLoggingIn,
                        decoration: const InputDecoration(
                          labelText: 'Tài khoản',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: _passwordController,
                        enabled: !sync.isLoggingIn,
                        obscureText: true,
                        onSubmitted: (_) => _login(),
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      icon: sync.isLoggingIn
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login, size: 18),
                      label: const Text('Đăng nhập'),
                      onPressed: sync.isLoggingIn ? null : _login,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _UpdateSettings extends ConsumerStatefulWidget {
  const _UpdateSettings();

  @override
  ConsumerState<_UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends ConsumerState<_UpdateSettings> {
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _currentVersion = info.version);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkNow() async {
    await ref.read(updateControllerProvider.notifier).checkForUpdate();
    if (!mounted) return;
    final state = ref.read(updateControllerProvider);
    switch (state.phase) {
      case UpdatePhase.available:
        maybeShowUpdateDialog(context, ref);
      case UpdatePhase.upToDate:
        _showMessage(state.message ?? 'Bạn đang dùng bản mới nhất.');
      case UpdatePhase.error:
        _showMessage(state.message ?? 'Kiểm tra cập nhật thất bại.');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final checking =
        ref.watch(updateControllerProvider.select((s) => s.phase)) ==
        UpdatePhase.checking;

    return Column(
      children: [
        SettingsSwitchRow(
          title: 'Tự động kiểm tra cập nhật',
          description:
              'Kiểm tra bản mới trên GitHub mỗi khi khởi động ứng dụng.',
          value: settings.autoCheckUpdates,
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAutoCheckUpdates(value),
        ),
        SettingsControlRow(
          title: 'Kiểm tra cập nhật',
          description: _currentVersion.isEmpty
              ? 'Đang đọc phiên bản hiện tại...'
              : 'Phiên bản hiện tại: $_currentVersion',
          controlWidth: 210,
          control: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt_outlined),
              label: const Text('Kiểm tra ngay'),
              onPressed: checking ? null : _checkNow,
            ),
          ),
        ),
      ],
    );
  }
}
