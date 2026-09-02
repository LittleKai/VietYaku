import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../application/ai_settings_controller.dart';
import '../domain/ai_api_key.dart';
import '../domain/ai_service_config.dart';
import '../domain/ai_service_type.dart';

Future<void> showAiSettingsDialog(BuildContext context, WidgetRef ref) {
  return showAppDialog<void>(
    context: context,
    icon: Icons.auto_awesome,
    title: 'Cài đặt Dịch & Tra cứu AI',
    description:
        'Cấu hình các nhà cung cấp AI, quản lý API key và các tham số dịch thuật.',
    accentColor: const Color(0xFF8E24AA),
    width: 650,
    content: const _AiSettingsContent(),
    actionsBuilder: (dialogContext) => const [],
  );
}

class _AiSettingsContent extends ConsumerStatefulWidget {
  const _AiSettingsContent();

  @override
  ConsumerState<_AiSettingsContent> createState() => _AiSettingsContentState();
}

class _AiSettingsContentState extends ConsumerState<_AiSettingsContent> {
  late AiServiceType _selectedService;
  late Map<AiServiceType, AiServiceConfig> _configs;
  bool _initialized = false;
  int? _selectedKeyIndex;

  @override
  void initState() {
    super.initState();
    final current =
        ref.read(aiSettingsControllerProvider).valueOrNull ??
        AiSettings.defaults();
    _selectedService = current.activeService;
    _configs = Map.from(current.serviceConfigs);
    _initialized = true;
  }

  AiServiceConfig get _currentConfig =>
      _configs[_selectedService] ??
      AiServiceConfig.defaultsFor(_selectedService);

  void _updateCurrentConfig(AiServiceConfig newConfig) {
    setState(() {
      _configs[_selectedService] = newConfig;
    });
  }

  Future<void> _showAddKeyDialog() async {
    final controller = TextEditingController();
    bool obscure = true;

    final key = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Thêm API Key cho ${_selectedService.label}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nhập API Key. Key sẽ được lưu trữ an toàn trong máy của bạn.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      hintText: 'Dán API key vào đây...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      controller.text = data!.text!.trim();
                    }
                  },
                  child: const Text('Dán từ clipboard'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogCtx).pop(controller.text.trim()),
                  child: const Text('Thêm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (key != null && key.isNotEmpty) {
      if (!_currentConfig.keys.any((k) => k.value == key)) {
        _updateCurrentConfig(
          _currentConfig.copyWith(
            keys: [..._currentConfig.keys, AiApiKey(key)],
          ),
        );
      }
    }
  }

  void _setKeyWeight(int index, int weight) {
    final keys = List<AiApiKey>.from(_currentConfig.keys);
    if (index < 0 || index >= keys.length) return;
    keys[index] = keys[index].copyWith(weight: weight);
    _updateCurrentConfig(_currentConfig.copyWith(keys: keys));
  }

  void _removeSelectedKey() {
    if (_selectedKeyIndex == null) return;
    final keys = List<AiApiKey>.from(_currentConfig.keys);
    if (_selectedKeyIndex! >= 0 && _selectedKeyIndex! < keys.length) {
      keys.removeAt(_selectedKeyIndex!);
      _updateCurrentConfig(_currentConfig.copyWith(keys: keys));
      setState(() {
        _selectedKeyIndex = null;
      });
    }
  }

  void _clearAllKeys() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc chắn muốn xóa toàn bộ key của ${_selectedService.label}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateCurrentConfig(_currentConfig.copyWith(keys: const []));
              setState(() {
                _selectedKeyIndex = null;
              });
            },
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );
  }


  Future<void> _saveAll() async {
    // Lấy messenger trước khi pop — sau pop thì context của dialog không tra
    // ngược cây widget được nữa.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(aiSettingsControllerProvider.notifier);

    await notifier.setActiveService(_selectedService);
    for (final entry in _configs.entries) {
      await notifier.updateServiceConfig(entry.key, entry.value);
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Đã lưu cài đặt AI thành công!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final config = _currentConfig;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Chọn Dịch vụ AI (Segmented / Dropdown)
          Text('Nhà cung cấp AI:', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownMenu<AiServiceType>(
            expandedInsets: EdgeInsets.zero,
            initialSelection: _selectedService,
            onSelected: (value) {
              if (value != null) {
                setState(() {
                  _selectedService = value;
                  _selectedKeyIndex = null;
                });
              }
            },
            dropdownMenuEntries: [
              for (final type in AiServiceType.values)
                DropdownMenuEntry(
                  value: type,
                  label: '${type.label} (${_configs[type]?.keys.length ?? 0} keys)',
                ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. Danh sách API Keys
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Danh sách API Keys (${config.keys.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Xoay vòng theo trọng số (weight ${config.keys.fold(0, (sum, k) => sum + k.weight)} lượt/chu kỳ)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 130,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: config.keys.isEmpty
                      ? const Center(
                          child: Text(
                            'Chưa có API key nào được thêm.\nNhấn "Thêm key" để nhập.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        )
                      : ListView.builder(
                          itemCount: config.keys.length,
                          itemBuilder: (context, index) {
                            final key = config.keys[index];
                            final isSelected = _selectedKeyIndex == index;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor:
                                  scheme.primaryContainer.withValues(alpha: 0.3),
                              leading: Text(
                                '#${index + 1}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              title: Text(
                                AiSettings.maskKey(key.value),
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 13,
                                ),
                              ),
                              trailing: _KeyWeightStepper(
                                weight: key.weight,
                                onChanged: (w) => _setKeyWeight(index, w),
                              ),
                              onTap: () => setState(() {
                                _selectedKeyIndex = isSelected ? null : index;
                              }),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _showAddKeyDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm key'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _selectedKeyIndex != null ? _removeSelectedKey : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa key'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          config.keys.isNotEmpty ? _clearAllKeys : null,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Xóa tất cả'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Weight = số lượt gọi của key đó trong mỗi chu kỳ xoay vòng. '
                  'Key weight 3 được dùng gấp 3 lần key weight 1; đặt cao cho '
                  'key còn nhiều hạn ngạch.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 3. Cấu hình Model
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chọn Mô hình (Model):',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  initialSelection: config.selectedModel,
                  onSelected: (value) {
                    if (value != null && value.isNotEmpty) {
                      _updateCurrentConfig(
                        config.copyWith(selectedModel: value),
                      );
                    }
                  },
                  dropdownMenuEntries: [
                    for (final model in _selectedService.availableModels)
                      DropdownMenuEntry(value: model, label: model),
                  ],
                ),
                if (_selectedService == AiServiceType.geminiCli) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '• gemini-3-flash-preview: Tiết kiệm token, sạch và nhanh.\n'
                      '• 假流式-agy-gemini-3.6-flash-low: Chất lượng dịch văn học/tiểu thuyết cao nhất.\n'
                      '• agy-*: Tiêu chuẩn, thích hợp tra cứu nhanh câu/từ đơn.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 4. Tham số nâng cao (Parameters)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tham số gọi API:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Temperature
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text('Temperature: ${config.temperature.toStringAsFixed(2)}'),
                    ),
                    Expanded(
                      child: Slider(
                        value: config.temperature,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        label: config.temperature.toStringAsFixed(2),
                        onChanged: (v) => _updateCurrentConfig(
                          config.copyWith(temperature: v),
                        ),
                      ),
                    ),
                  ],
                ),

                // Top P
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text('Top P: ${config.topP.toStringAsFixed(2)}'),
                    ),
                    Expanded(
                      child: Slider(
                        value: config.topP,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: config.topP.toStringAsFixed(2),
                        onChanged: (v) => _updateCurrentConfig(
                          config.copyWith(topP: v),
                        ),
                      ),
                    ),
                  ],
                ),

                // Max Tokens & Timeout
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Max Tokens (${config.maxTokens}):', style: theme.textTheme.bodySmall),
                          Slider(
                            value: config.maxTokens.toDouble(),
                            min: 1000,
                            max: 32000,
                            divisions: 31,
                            label: '${config.maxTokens}',
                            onChanged: (v) => _updateCurrentConfig(
                              config.copyWith(maxTokens: v.toInt()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Timeout (${config.timeout}s):', style: theme.textTheme.bodySmall),
                          Slider(
                            value: config.timeout.toDouble(),
                            min: 10,
                            max: 600,
                            divisions: 59,
                            label: '${config.timeout}s',
                            onChanged: (v) => _updateCurrentConfig(
                              config.copyWith(timeout: v.toInt()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Hủy'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saveAll,
                icon: const Icon(Icons.save),
                label: const Text('Lưu cài đặt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ô chỉnh trọng số của một key: `-` / số / `+`, kẹp trong [AiApiKey.minWeight]
/// và [AiApiKey.maxWeight].
class _KeyWeightStepper extends StatelessWidget {
  const _KeyWeightStepper({required this.weight, required this.onChanged});

  final int weight;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Giảm weight',
          onPressed: weight > AiApiKey.minWeight
              ? () => onChanged(weight - 1)
              : null,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
        ),
        Tooltip(
          message: 'Weight $weight — số lượt gọi mỗi chu kỳ xoay vòng',
          child: Container(
            constraints: const BoxConstraints(minWidth: 28),
            alignment: Alignment.center,
            child: Text(
              '$weight',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Tăng weight',
          onPressed: weight < AiApiKey.maxWeight
              ? () => onChanged(weight + 1)
              : null,
          icon: const Icon(Icons.add_circle_outline, size: 18),
        ),
      ],
    );
  }
}
