import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tts_service.dart';
import '../dictionary/application/dictionaries_provider.dart';
import '../dictionary_sync/application/dictionary_sync_controller.dart';
import '../repair/domain/jp_repair_pipeline.dart';
import '../repair/presentation/repair_screen.dart';
import '../translation/domain/translation_engine.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // Màu cho tiêu đề từng nhóm cài đặt.
  static const _titleColors = <Color>[
    Color(0xFF1565C0), // xanh dương
    Color(0xFF2E7D32), // xanh lá
    Color(0xFF6A1B9A), // tím
    Color(0xFFC62828), // đỏ
    Color(0xFFE65100), // cam
    Color(0xFF00838F), // cyan
  ];

  Widget _sectionTitle(BuildContext context, String text, int index) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      color: _titleColors[index % _titleColors.length],
      fontWeight: FontWeight.bold,
    ),
  );


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(context, 'Thuật toán dịch', 0),
        const SizedBox(height: 4),
        Text(
          'Thay đổi áp dụng ở lần bấm Dịch tiếp theo.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<TranslationAlgorithm>(
            segments: const [
              ButtonSegment(
                value: TranslationAlgorithm.leftToRight,
                label: Text('Trái → phải'),
                tooltip: 'Quét trái sang phải, mỗi vị trí lấy cụm dài nhất',
              ),
              ButtonSegment(
                value: TranslationAlgorithm.longestPhrase,
                label: Text('Ưu tiên cụm dài'),
                tooltip: 'Cụm dài nhất toàn văn bản được dịch trước',
              ),
              ButtonSegment(
                value: TranslationAlgorithm.longestPhrase4,
                label: Text('Cụm dài ≥ 4'),
                tooltip: 'Chỉ cụm từ 4 ký tự trở lên được ưu tiên toàn văn',
              ),
            ],
            selected: {settings.translationAlgorithm},
            onSelectionChanged: (selection) =>
                notifier.setTranslationAlgorithm(selection.first),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ưu tiên Name hơn VietPhrase'),
          subtitle: const Text(
            'Match Names tại một vị trí thắng cụm VietPhrase dài hơn '
            '(UserDict vẫn cao nhất).',
          ),
          value: settings.prioritizeNames,
          onChanged: (value) => notifier.setPrioritizeNames(value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Chuẩn hoá katakana nửa hình (ｱｲｳ → アイウ)'),
          subtitle: const Text(
            'Mode Nhật: đổi halfwidth katakana về fullwidth trước khi tra '
            'từ điển (kể cả ｶﾞ → ガ).',
          ),
          value: settings.normalizeHalfwidthKana,
          onChanged: (value) => notifier.setNormalizeHalfwidthKana(value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gộp số kanji thành số Ả Rập (三百二十五 → 325)'),
          subtitle: const Text(
            'Mode Nhật: run số kanji không có trong từ điển được gộp và đổi '
            'sang số Ả Rập; cụm đã match (vd 一人) giữ nguyên.',
          ),
          value: settings.joinKanjiNumerals,
          onChanged: (value) => notifier.setJoinKanjiNumerals(value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Từ điển biến thể Sudachi (打込む → 打ち込む)'),
          subtitle: const Text(
            'Mode Nhật: tra được biến thể okurigana/chữ khác của từ đã có '
            'trong VietPhrase (data/jp/SudachiVariants.txt). '
            'Đổi setting sẽ nạp lại từ điển.',
          ),
          value: settings.sudachiVariants,
          onChanged: (value) => notifier.setSudachiVariants(value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Phát âm kana từ SudachiDict trong ô Nghĩa'),
          subtitle: const Text(
            'Mode Nhật: khi Nhật Việt/Lạc Việt không có phát âm, lấy kana '
            'từ data/jp/SudachiReadings.txt.',
          ),
          value: settings.sudachiReadings,
          onChanged: (value) => notifier.setSudachiReadings(value),
        ),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Phát âm (TTS)', 1),
        const SizedBox(height: 8),
        const _TtsSettings(),
        // Sửa từ điển + đồng bộ file: chỉ dành cho desktop (ẩn trên Android).
        if (!Platform.isAndroid) ...[
          const SizedBox(height: 24),
          _sectionTitle(context, 'Sửa từ điển — Key thuần Hán', 2),
          const SizedBox(height: 4),
          Text(
            'Chính sách áp dụng khi bấm Run trong tab Sửa từ điển.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<RepairPolicy>(
              segments: const [
                ButtonSegment(
                  value: RepairPolicy.addVariant,
                  label: Text('Giữ gốc + thêm bản JP'),
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
          const SizedBox(height: 8),
          // Công cụ sửa từ điển (chuyển từ tab riêng vào Cài đặt).
          Card(
            margin: EdgeInsets.zero,
            child: const RepairScreen(),
          ),
          const SizedBox(height: 24),
          const _DictionarySyncSettings(),
        ],
        const SizedBox(height: 24),
        _sectionTitle(context, 'Từ điển', 3),
        const SizedBox(height: 4),
        Text(
          'Mỗi ngôn ngữ một bộ riêng (data/jp, data/cn trong dự án). Với tiếng '
          'Nhật, file đã sửa (*_JP.txt trong dữ liệu app) tự động được ưu tiên '
          'hơn file gốc.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.refresh),
            label: const Text('Nạp lại từ điển'),
            onPressed: () => ref.read(dictionariesProvider.notifier).reload(),
          ),
        ),
      ],
    );
  }
}

/// Cài đặt phát âm: tốc độ đọc + chọn giọng cho từng ngôn ngữ.
class _TtsSettings extends ConsumerWidget {
  const _TtsSettings();

  static const _samples = <TranslationMode, String>{
    TranslationMode.japanese: 'こんにちは',
    TranslationMode.chinese: '你好',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final tts = ref.watch(ttsServiceProvider).valueOrNull;
    final ratePct = (settings.ttsSpeechRate * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 90, child: Text('Tốc độ')),
            Expanded(
              child: Slider(
                value: settings.ttsSpeechRate,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                label: '$ratePct%',
                onChanged: notifier.setTtsSpeechRate,
              ),
            ),
            SizedBox(width: 48, child: Text('$ratePct%')),
          ],
        ),
        const SizedBox(height: 4),
        for (final mode in TranslationMode.values)
          _voiceRow(context, ref, mode, settings, tts),
      ],
    );
  }

  Widget _voiceRow(
    BuildContext context,
    WidgetRef ref,
    TranslationMode mode,
    AppSettings settings,
    TtsService? tts,
  ) {
    final label = mode == TranslationMode.japanese ? 'Nhật' : 'Trung';
    final voices = tts?.voicesFor(mode) ?? const <Map<String, String>>[];
    final available = tts?.availableFor(mode) ?? false;

    if (!available || voices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(label)),
            Expanded(
              child: Text(
                'Chưa có giọng ${TtsService.languageFor(mode)} trên máy.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final current = settings.ttsVoiceFor(mode);
    final entries = <DropdownMenuEntry<String>>[
      const DropdownMenuEntry(value: '', label: 'Tự động'),
      for (final v in voices)
        DropdownMenuEntry(
          value: TtsService.voiceKeyOf(v),
          label: v['name'] ?? '',
        ),
    ];
    final initial = entries.any((e) => e.value == current) ? current : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: DropdownMenu<String>(
              key: ValueKey('tts:${mode.name}:$initial'),
              initialSelection: initial,
              label: const Text('Giọng đọc'),
              expandedInsets: EdgeInsets.zero,
              onSelected: (value) =>
                  ref.read(settingsProvider.notifier).setTtsVoice(mode, value ?? ''),
              dropdownMenuEntries: entries,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: 'Nghe thử',
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
  late final TextEditingController _serverController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: ref.read(settingsProvider).syncServerUrl,
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final url = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _showMessage('Địa chỉ server không hợp lệ.');
      return;
    }
    if (username.isEmpty || password.isEmpty) {
      _showMessage('Hãy nhập tài khoản và mật khẩu.');
      return;
    }

    await ref.read(settingsProvider.notifier).setSyncServerUrl(url);
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final sync = ref.watch(dictionarySyncProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Từ điển chung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: 420,
          child: TextField(
            controller: _serverController,
            enabled: !settings.isSyncServerUrlOverridden && !sync.isAdmin && !sync.isLoggingIn,
            decoration: InputDecoration(
              labelText: 'Địa chỉ LittleKai server',
              prefixIcon: const Icon(Icons.dns_outlined),
              helperText: settings.isSyncServerUrlOverridden ? 'Được cấu hình từ file .env (chỉ đọc)' : null,
              helperStyle: settings.isSyncServerUrlOverridden ? const TextStyle(color: Colors.green) : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (sync.session case final session?)
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 20),
              const SizedBox(width: 8),
              Text(session.username),
              const SizedBox(width: 12),
              TextButton.icon(
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Đăng xuất'),
                onPressed: () =>
                    ref.read(dictionarySyncProvider.notifier).logout(),
              ),
            ],
          )
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _usernameController,
                  enabled: !sync.isLoggingIn,
                  decoration: const InputDecoration(
                    labelText: 'Tài khoản admin',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
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
        ],
      ],
    );
  }
}
