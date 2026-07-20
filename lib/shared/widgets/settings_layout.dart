import 'package:flutter/material.dart';

/// Khung trang dùng chung cho các màn hình cấu hình.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (
                    var index = 0;
                    index < widget.children.length;
                    index++
                  ) ...[
                    widget.children[index],
                    if (index != widget.children.length - 1)
                      const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Một nhóm cài đặt có header và các hàng lựa chọn tách bạch.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _resolvedAccent(context, accentColor ?? scheme.primary);
    return _SettingsAccent(
      color: accent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: scheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsIcon(icon: icon, prominent: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: accent,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  Divider(height: 1, indent: 16, color: scheme.outlineVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hàng cài đặt dạng bật/tắt. Toàn bộ hàng là vùng bấm.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _SettingsCopy(title: title, description: description),
            ),
            const SizedBox(width: 16),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Hàng cài đặt chứa dropdown, slider, segmented button hoặc hành động.
class SettingsControlRow extends StatelessWidget {
  const SettingsControlRow({
    super.key,
    required this.title,
    required this.description,
    required this.control,
    this.controlWidth = 430,
  });

  final String title;
  final String description;
  final Widget control;
  final double controlWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final copy = _SettingsCopy(title: title, description: description);

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 14), control],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 24),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: controlWidth),
                child: control,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsCopy extends StatelessWidget {
  const _SettingsCopy({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, this.prominent = false});

  final IconData icon;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _SettingsAccent.of(context) ?? scheme.primary;
    final size = prominent ? 40.0 : 36.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: prominent ? 0.18 : 0.12),
          scheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: prominent ? 22 : 20, color: accent),
    );
  }
}

Color _resolvedAccent(BuildContext context, Color color) {
  if (Theme.of(context).brightness == Brightness.light) return color;
  return Color.lerp(color, Colors.white, 0.34)!;
}

class _SettingsAccent extends InheritedWidget {
  const _SettingsAccent({required this.color, required super.child});

  final Color color;

  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsAccent>()?.color;

  @override
  bool updateShouldNotify(_SettingsAccent oldWidget) =>
      color != oldWidget.color;
}
