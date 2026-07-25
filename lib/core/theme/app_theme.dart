import 'package:flutter/material.dart';

/// Hệ thiết kế tập trung của VietYaku.
///
/// Toàn bộ dialog, ô nhập (edittext), dropdown, tab, nút, panel… lấy style từ
/// đây — không style rời rạc ở từng widget. Có bản sáng/tối; tối tự theo hệ
/// điều hành qua `ThemeMode.system`.
class AppTheme {
  AppTheme._();

  /// Indigo tinh chỉnh — giữ bản sắc cũ nhưng sạch và hiện đại hơn.
  static const Color _seed = Color(0xFF4F46E5);

  /// Font chrome mặc định (nhãn/tiêu đề/nút). Segoe UI hiển thị tốt dấu tiếng
  /// Việt và tự fallback CJK trên Windows, không cần đóng gói font → giữ offline
  /// thuần. Người dùng có thể đổi font/cỡ chữ giao diện trong tab Giao diện.
  static const String _fontFamily = 'Segoe UI';

  /// [fontFamily] rỗng → dùng [_fontFamily]. [fontScale] scale cỡ chữ chrome
  /// (không đụng nội dung các ô dịch — ô dùng cỡ tuyệt đối riêng).
  static ThemeData light({String fontFamily = '', double fontScale = 1.0}) =>
      _build(Brightness.light, fontFamily, fontScale);
  static ThemeData dark({String fontFamily = '', double fontScale = 1.0}) =>
      _build(Brightness.dark, fontFamily, fontScale);

  static ThemeData _build(
    Brightness brightness,
    String fontFamily,
    double fontScale,
  ) {
    final bool isDark = brightness == Brightness.dark;
    final String family = fontFamily.trim().isEmpty
        ? _fontFamily
        : fontFamily.trim();
    final ColorScheme scheme = _refine(
      ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
    );

    final ThemeData base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      fontFamily: family,
      scaffoldBackgroundColor: scheme.surface,
    );

    // Scale cỡ chữ giao diện: chỉ áp lên text lấy từ theme (chrome), không đụng
    // các ô dịch (chúng đặt fontSize tuyệt đối, độc lập textTheme).
    final TextTheme text = fontScale == 1.0
        ? _textTheme(base.textTheme)
        : _textTheme(base.textTheme).apply(fontSizeFactor: fontScale);

    // Bo góc thống nhất theo cấp: nút/ô nhập < menu/card < dialog.
    final OutlinedBorder buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    // Nền ô nhập / edittext: nhuộm nhẹ sắc thương hiệu (indigo-white) thay cho
    // xám neutral đậm nhất của M3 (surfaceContainerHighest). Nhờ vậy các ô lớn
    // (Nguồn, Bản dịch Việt, các ô trong dialog) đọc như vùng nhập mềm, không
    // còn là khối xám phẳng nặng; viền outlineVariant lo phần phân định.
    final Color inputFill = _mix(
      scheme.surface,
      scheme.primary,
      isDark ? 0.11 : 0.07,
    );

    return base.copyWith(
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      // ── Ô nhập / edittext ────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodySmall?.copyWith(color: scheme.primary),
        border: inputBorder(scheme.outlineVariant),
        enabledBorder: inputBorder(scheme.outlineVariant),
        focusedBorder: inputBorder(scheme.primary, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
      ),

      // ── Dropdown (DropdownMenu M3) ───────────────────────────────────────
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: inputFill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: inputBorder(scheme.outlineVariant),
          enabledBorder: inputBorder(scheme.outlineVariant),
          focusedBorder: inputBorder(scheme.primary, 2),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),

      // ── Menu / popup ─────────────────────────────────────────────────────
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Dialog ───────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      ),

      // ── Nút ──────────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStatePropertyAll(scheme.outlineVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),

      // ── Điều hướng / tab ────────────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        useIndicator: true,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
        dividerColor: scheme.outlineVariant,
        dividerHeight: 1,
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.06),
        ),
      ),

      // ── Bề mặt ───────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurface,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      // ── Phản hồi / trạng thái ───────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        waitDuration: const Duration(milliseconds: 450),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: text.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      // ── Token màu ngữ nghĩa ngoài ColorScheme (tô nổi, token Names) ──────
      extensions: <ThemeExtension<dynamic>>[
        isDark
            ? const AppSemanticColors(
                highlight: Color(0xFFFF8A80),
                nameToken: Color(0xFF4DB6AC),
              )
            : const AppSemanticColors(
                highlight: Color(0xFFD32F2F),
                nameToken: Color(0xFF00796B),
              ),
      ],
    );
  }

  /// Kéo màu `base` về phía `target` theo tỉ lệ `t` (0..1).
  static Color _mix(Color base, Color target, double t) =>
      Color.lerp(base, target, t)!;

  /// Tinh chỉnh bảng màu do `fromSeed` sinh ra để bớt "xám mặc định":
  /// chữ phụ và viền rõ hơn (tăng tương phản), nền/bề mặt được nhuộm nhẹ sắc
  /// thương hiệu thay vì xám phẳng. Không đụng các role văn bản chính hay màu
  /// nhấn — chỉ nâng nhóm bị nhạt/khó nhìn. Áp cho cả bản sáng lẫn tối.
  static ColorScheme _refine(ColorScheme s) {
    final bool isDark = s.brightness == Brightness.dark;
    return s.copyWith(
      // Chữ phụ / hint / nhãn / icon phụ: kéo về phía chữ chính cho dễ đọc,
      // thêm chút sắc thương hiệu để không còn xám chết.
      onSurfaceVariant: _mix(
        _mix(s.onSurfaceVariant, s.onSurface, isDark ? 0.16 : 0.24),
        s.primary,
        0.10,
      ),
      // Viền ô nhập / card / divider: rõ hơn hẳn, không còn gần như tàng hình.
      outlineVariant: _mix(s.outlineVariant, s.outline, 0.45),
      outline: _mix(s.outline, s.onSurface, isDark ? 0.06 : 0.12),
      // Nền & các lớp bề mặt (scaffold, dialog, rail, menu, card): nhuộm nhẹ
      // sắc thương hiệu để thoát khỏi xám phẳng, vẫn giữ tương phản chữ.
      surface: _mix(s.surface, s.primary, isDark ? 0.030 : 0.018),
      surfaceContainerLowest: _mix(
        s.surfaceContainerLowest,
        s.primary,
        isDark ? 0.030 : 0.020,
      ),
      surfaceContainerLow: _mix(
        s.surfaceContainerLow,
        s.primary,
        isDark ? 0.035 : 0.025,
      ),
      surfaceContainer: _mix(
        s.surfaceContainer,
        s.primary,
        isDark ? 0.040 : 0.030,
      ),
      surfaceContainerHigh: _mix(
        s.surfaceContainerHigh,
        s.primary,
        isDark ? 0.045 : 0.035,
      ),
      surfaceContainerHighest: _mix(
        s.surfaceContainerHighest,
        s.primary,
        isDark ? 0.050 : 0.040,
      ),
    );
  }

  /// Thang chữ product: một họ font, tương phản qua cỡ + độ đậm.
  static TextTheme _textTheme(TextTheme b) => b.copyWith(
    headlineSmall: b.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
    ),
    titleLarge: b.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    titleMedium: b.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleSmall: b.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: b.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
  );
}

/// Màu ngữ nghĩa của app không có trong `ColorScheme` chuẩn.
/// Có bản riêng cho nền sáng/tối để luôn đủ tương phản.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  /// Tô nổi cụm đang chọn (đồng bộ 3 pane).
  final Color highlight;

  /// Token khớp từ điển Names.
  final Color nameToken;

  const AppSemanticColors({required this.highlight, required this.nameToken});

  /// Đọc nhanh trong widget; fallback an toàn nếu chưa gắn extension.
  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ??
      const AppSemanticColors(
        highlight: Color(0xFFD32F2F),
        nameToken: Color(0xFF00796B),
      );

  @override
  AppSemanticColors copyWith({Color? highlight, Color? nameToken}) =>
      AppSemanticColors(
        highlight: highlight ?? this.highlight,
        nameToken: nameToken ?? this.nameToken,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      highlight: Color.lerp(highlight, other.highlight, t)!,
      nameToken: Color.lerp(nameToken, other.nameToken, t)!,
    );
  }
}
