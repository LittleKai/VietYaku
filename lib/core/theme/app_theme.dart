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

    // Viền dày hơn 1px để "ăn" được trên nền sáng, không bị tan biến.
    const double borderWidth = 1.3;

    OutlineInputBorder inputBorder(Color color, [double width = borderWidth]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    // Nền ô nhập / edittext: lấy lớp bề mặt SÁNG NHẤT (gần trắng ở nền sáng)
    // thay vì xám neutral của M3. Ô nhập trở thành vùng sáng rõ, phần phân
    // định do viền outlineVariant sắc nét đảm nhiệm — không còn khối xám mờ.
    final Color inputFill = scheme.surfaceContainerLowest;

    // Bề mặt nổi (card, ô nhập, chip chưa chọn): sáng hơn nền scaffold nên
    // đọc như đang nâng lên khỏi canvas.
    final Color raised = scheme.surfaceContainerLowest;

    // Bóng nhuộm sắc thương hiệu thay vì đen thuần — bóng đen trên nền đã
    // nhuộm indigo trông bẩn và "đục".
    final Color shadow = _mix(scheme.primary, Colors.black, isDark ? 0.72 : 0.3);

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
        textStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: inputFill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          floatingLabelStyle: text.bodySmall?.copyWith(color: scheme.primary),
          border: inputBorder(scheme.outlineVariant),
          enabledBorder: inputBorder(scheme.outlineVariant),
          focusedBorder: inputBorder(scheme.primary, 2),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(raised),
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
          backgroundColor: WidgetStatePropertyAll(raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(shadow),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant, width: borderWidth),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant, width: borderWidth),
        ),
      ),

      // ── Dialog ───────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant, width: borderWidth),
        ),
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
          elevation: 2,
          shadowColor: shadow,
        ).copyWith(
          // Bóng nhấn theo trạng thái: nghỉ nổi nhẹ, hover nổi rõ, bấm thì
          // dán xuống — nút có cảm giác vật lý thay vì phẳng bệt.
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return 0.0;
            if (states.contains(WidgetState.pressed)) return 0.0;
            if (states.contains(WidgetState.hovered)) return 5.0;
            return 2.0;
          }),
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
          backgroundColor: raised,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline, width: borderWidth),
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
      // Segment đang chọn: tô đặc màu nhấn (không còn container xám nhạt);
      // segment chưa chọn: nền sáng nổi + viền sắc nét, không phẳng bệt.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainerHigh;
            }
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return raised;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) return scheme.onPrimary;
            return scheme.onSurfaceVariant;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onPrimary.withValues(alpha: 0.12);
            }
            return scheme.primary.withValues(alpha: 0.10);
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: scheme.primary, width: borderWidth);
            }
            return BorderSide(color: scheme.outlineVariant, width: borderWidth);
          }),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ),

      // FilterChip / ChoiceChip: chưa chọn là ô sáng viền rõ, đã chọn nhuộm
      // đậm màu nhấn kèm viền cùng tông — trạng thái active nhìn là thấy.
      chipTheme: ChipThemeData(
        backgroundColor: raised,
        selectedColor: _mix(raised, scheme.primary, isDark ? 0.34 : 0.18),
        disabledColor: scheme.surfaceContainerHigh,
        checkmarkColor: scheme.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: scheme.primary, width: 1.6);
          }
          return BorderSide(color: scheme.outlineVariant, width: borderWidth);
        }),
        // Màu nhãn phải là WidgetStateColor: Chip chỉ resolve theo trạng thái ở
        // thuộc tính `color`, còn WidgetStateTextStyle bị nó làm mất kiểu chữ.
        labelStyle: text.labelLarge?.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      // ── Điều hướng / tab ────────────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: raised,
        // Icon từng mục có màu riêng nên viên chỉ báo dùng nền nhuộm nhấn +
        // viền, không tô đặc — giữ được màu icon mà vẫn rõ mục đang chọn.
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
        ),
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        useIndicator: true,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.titleSmall,
        dividerColor: scheme.outlineVariant,
        dividerHeight: 1,
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.08),
        ),
      ),

      // ── Bề mặt ───────────────────────────────────────────────────────────
      // Card nổi hẳn lên: nền sáng nhất (không phải xám surfaceContainerLow),
      // viền sắc nét và bóng nhuộm sắc thương hiệu.
      cardTheme: CardThemeData(
        elevation: 3,
        color: raised,
        shadowColor: shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant, width: borderWidth),
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
      // Slider: rãnh chưa chạy cũng mang màu nhấn (nhạt) thay vì xám chết,
      // rãnh dày hơn và núm có bóng → thấy rõ ở mọi cỡ chữ.
      sliderTheme: SliderThemeData(
        trackHeight: 7,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: _mix(raised, scheme.primary, isDark ? 0.32 : 0.24),
        secondaryActiveTrackColor: scheme.primary.withValues(alpha: 0.45),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.16),
        activeTickMarkColor: scheme.onPrimary.withValues(alpha: 0.55),
        inactiveTickMarkColor: scheme.primary.withValues(alpha: 0.45),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: text.labelMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: _mix(raised, scheme.primary, isDark ? 0.30 : 0.20),
        circularTrackColor: _mix(raised, scheme.primary, isDark ? 0.30 : 0.20),
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

  /// Dựng lại bảng màu `fromSeed` theo hướng **tươi sáng, rực rỡ**.
  ///
  /// `fromSeed` giảm mạnh sắc độ nhóm neutral nên mọi bề mặt ra xám đục và
  /// màu nhấn bị nhạt đi so với seed. Ở đây:
  /// - `primary` kéo về đúng seed (bản tối thì sáng lên để đủ tương phản);
  /// - toàn bộ lớp bề mặt pha lại **từ trắng** (nền sáng) / từ than nhuộm
  ///   indigo (nền tối), theo thang tăng dần → sắc thương hiệu thấy được;
  /// - lớp nổi (`surfaceContainerLowest/Low` — card, ô nhập, menu) SÁNG HƠN
  ///   nền scaffold nên card nổi lên khỏi canvas thay vì chìm;
  /// - `onSurfaceVariant` / `outline*` tăng tương phản mạnh để chữ mô tả và
  ///   viền không còn mờ;
  /// - `secondaryContainer` nạp màu nhấn để badge số và vùng active nổi bật.
  static ColorScheme _refine(ColorScheme s) {
    final bool isDark = s.brightness == Brightness.dark;

    final Color primary = isDark ? _mix(_seed, Colors.white, 0.45) : _seed;
    final Color onPrimary = isDark
        ? _mix(_seed, Colors.black, 0.74)
        : Colors.white;

    if (isDark) {
      // Chế độ Tối: Nền đen/than trung tính (sạch, sắc nét, không tím đục)
      const Color darkSurface = Color(0xFF121214);
      const Color darkLowest = Color(0xFF1E1E22);
      const Color darkLow = Color(0xFF222226);
      const Color darkContainer = Color(0xFF26262B);
      const Color darkHigh = Color(0xFF2B2B30);
      const Color darkHighest = Color(0xFF303036);

      return s.copyWith(
        primary: primary,
        onPrimary: onPrimary,
        inversePrimary: _seed,
        surface: darkSurface,
        surfaceContainerLowest: darkLowest,
        surfaceContainerLow: darkLow,
        surfaceContainer: darkContainer,
        surfaceContainerHigh: darkHigh,
        surfaceContainerHighest: darkHighest,
        secondaryContainer: _mix(darkHigh, primary, 0.28),
        onSecondaryContainer: _mix(primary, Colors.white, 0.40),
        primaryContainer: _mix(darkHigh, primary, 0.35),
        onPrimaryContainer: _mix(primary, Colors.white, 0.45),
        onSurface: const Color(0xFFE6E1E5),
        onSurfaceVariant: const Color(0xFFCAC4D0),
        outlineVariant: const Color(0xFF49454F),
        outline: const Color(0xFF938F99),
      );
    }

    Color layer(Color darkBase, double lightT, double darkT) =>
        _mix(Colors.white, primary, lightT);

    return s.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      inversePrimary: _mix(_seed, Colors.white, 0.55),

      secondaryContainer: _mix(Colors.white, primary, 0.19),
      onSecondaryContainer: _mix(primary, Colors.black, 0.22),
      primaryContainer: _mix(Colors.white, primary, 0.24),
      onPrimaryContainer: _mix(primary, Colors.black, 0.28),

      onSurfaceVariant: _mix(
        _mix(s.onSurfaceVariant, s.onSurface, 0.46),
        primary,
        0.12,
      ),
      outlineVariant: _mix(s.outlineVariant, primary, 0.34),
      outline: _mix(s.outline, primary, 0.40),

      surface: layer(s.surface, 0.025, 0.09),
      surfaceContainerLowest: layer(s.surfaceContainerLowest, 0.005, 0.22),
      surfaceContainerLow: layer(s.surfaceContainerLow, 0.010, 0.20),
      surfaceContainer: layer(s.surfaceContainer, 0.020, 0.20),
      surfaceContainerHigh: layer(s.surfaceContainerHigh, 0.035, 0.20),
      surfaceContainerHighest: layer(s.surfaceContainerHighest, 0.20, 0.20),
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
    // Chữ mô tả (bodySmall) là nơi hay bị chìm nhất: nhích cỡ, dày hơn một
    // nấc và giãn dòng để đọc thoải mái ở nền sáng.
    bodySmall: b.bodySmall?.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1.38,
    ),
    bodyMedium: b.bodyMedium?.copyWith(height: 1.36),
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
