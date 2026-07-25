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
    // Card sáng nổi trên canvas: nền sáng nhất + viền sắc nét + bóng nhuộm
    // theo màu nhấn của section (không dùng bóng đen thuần → không bị đục).
    final surface = scheme.surfaceContainerLowest;
    final headerFill = Color.alphaBlend(
      accent.withValues(alpha: 0.10),
      surface,
    );
    final rowDivider = scheme.outlineVariant.withValues(alpha: 0.55);

    return _SettingsAccent(
      color: accent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Color.alphaBlend(accent.withValues(alpha: 0.28), surface),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 6),
              spreadRadius: -6,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header nhuộm màu nhấn + dải màu bên trái: mỗi nhóm cài đặt có
              // bản sắc riêng, không còn là dãy hộp xám giống hệt nhau.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: headerFill,
                  border: Border(
                    left: BorderSide(color: accent, width: 4),
                    bottom: BorderSide(color: rowDivider),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
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
              ),
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  Divider(height: 1, indent: 16, color: rowDivider),
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
    // Ô icon tô đặc màu nhấn: điểm màu mạnh nhất của mỗi nhóm cài đặt.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.34),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: prominent ? 22 : 20,
        color: _onAccent(accent),
      ),
    );
  }
}

Color _resolvedAccent(BuildContext context, Color color) {
  if (Theme.of(context).brightness == Brightness.light) return color;
  return Color.lerp(color, Colors.white, 0.34)!;
}

/// Chữ/icon đặt trên nền tô đặc màu nhấn — chọn theo độ sáng của nền.
Color _onAccent(Color accent) =>
    ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
    ? Colors.white
    : const Color(0xFF16121F);

/// Badge hiển thị giá trị số (%, cỡ chữ…) cạnh slider. Nền và viền mang màu
/// nhấn của nhóm cài đặt nên con số luôn đọc rõ, không chìm vào nền.
class SettingsValueBadge extends StatelessWidget {
  const SettingsValueBadge({super.key, required this.label, this.width = 58});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _SettingsAccent.of(context) ?? scheme.primary;
    return Container(
      width: width,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.16),
          scheme.surfaceContainerLowest,
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.3),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
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
