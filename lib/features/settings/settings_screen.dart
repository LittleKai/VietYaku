import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dictionary/application/dictionaries_provider.dart';
import '../dictionary_sync/application/dictionary_sync_controller.dart';
import '../repair/domain/jp_repair_pipeline.dart';
import '../translation/domain/translation_engine.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _fontFamilies = <String>[
    '',
    'Segoe UI',
    'Yu Gothic UI',
    'Meiryo',
    'MS Gothic',
    'Microsoft YaHei',
    'SimSun',
    'Times New Roman',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Chế độ dịch mặc định',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<TranslationMode>(
            segments: const [
              ButtonSegment(
                value: TranslationMode.japanese,
                label: Text('Nhật'),
              ),
              ButtonSegment(
                value: TranslationMode.chinese,
                label: Text('Trung'),
              ),
            ],
            selected: {settings.defaultMode},
            onSelectionChanged: (selection) =>
                notifier.setDefaultMode(selection.first),
          ),
        ),
        const SizedBox(height: 24),
        Text('Thuật toán dịch', style: Theme.of(context).textTheme.titleMedium),
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
        const SizedBox(height: 24),
        Text(
          'Cỡ chữ & font các ô',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final id in PaneId.values)
          _PaneFontRow(
            id: id,
            font: settings.paneFontFor(id),
            fontFamilies: _fontFamilies,
            onSizeChanged: (value) => notifier.setPaneFont(id, size: value),
            onFamilyChanged: (value) => notifier.setPaneFont(id, family: value),
          ),
        const SizedBox(height: 24),
        Text(
          'Sửa từ điển — Key thuần Hán',
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
        const SizedBox(height: 24),
        const _DictionarySyncSettings(),
        const SizedBox(height: 24),
        Text('Từ điển', style: Theme.of(context).textTheme.titleMedium),
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

class _PaneFontRow extends StatelessWidget {
  const _PaneFontRow({
    required this.id,
    required this.font,
    required this.fontFamilies,
    required this.onSizeChanged,
    required this.onFamilyChanged,
  });

  final PaneId id;
  final PaneFont font;
  final List<String> fontFamilies;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<String> onFamilyChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(paneLabels[id]!)),
          Expanded(
            child: Slider(
              value: font.size,
              min: 10,
              max: 28,
              divisions: 18,
              label: '${font.size.round()}',
              onChanged: onSizeChanged,
            ),
          ),
          SizedBox(width: 34, child: Text('${font.size.round()}')),
          const SizedBox(width: 8),
          DropdownMenu<String>(
            key: ValueKey('${id.name}:${font.family}'),
            width: 220,
            initialSelection: fontFamilies.contains(font.family)
                ? font.family
                : '',
            label: const Text('Font'),
            onSelected: (value) => onFamilyChanged(value ?? ''),
            dropdownMenuEntries: [
              for (final family in fontFamilies)
                DropdownMenuEntry<String>(
                  value: family,
                  label: family.isEmpty ? 'Mặc định hệ thống' : family,
                  style: MenuItemButton.styleFrom(
                    textStyle: TextStyle(
                      fontFamily: family.isEmpty ? null : family,
                    ),
                  ),
                ),
            ],
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
            enabled: !sync.isAdmin && !sync.isLoggingIn,
            decoration: const InputDecoration(
              labelText: 'Địa chỉ LittleKai server',
              prefixIcon: Icon(Icons.dns_outlined),
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
