import 'package:material_ui/material_ui.dart';

abstract final class AppColors {
  static const Color ink = Color(0xFF10231D);
  static const Color inkSoft = Color(0xFF1B342B);
  static const Color cream = Color(0xFFF3EFE5);
  static const Color paper = Color(0xFFFCFAF4);
  static const Color coral = Color(0xFFFF6C4E);
  static const Color coralSoft = Color(0xFFFFE2D9);
  static const Color lime = Color(0xFFD9FF78);
  static const Color limeSoft = Color(0xFFEDFFC0);
  static const Color moss = Color(0xFF2D6A53);
  static const Color sage = Color(0xFF9CB6A8);
  static const Color line = Color(0xFFE3DDCE);
  static const Color muted = Color(0xFF77827B);
  static const Color danger = Color(0xFFBF432F);
  static const Color sky = Color(0xFF9CD8ED);
}

abstract final class AppTheme {
  static const List<String> fontFallback = <String>[
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Segoe UI Variable',
    'Segoe UI',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static TextStyle _text({
    required double size,
    required FontWeight weight,
    Color color = AppColors.ink,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontFamilyFallback: fontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.ink,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.ink,
      onPrimary: AppColors.paper,
      primaryContainer: AppColors.inkSoft,
      onPrimaryContainer: AppColors.paper,
      secondary: AppColors.moss,
      onSecondary: AppColors.paper,
      secondaryContainer: AppColors.limeSoft,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.coral,
      onTertiary: AppColors.ink,
      tertiaryContainer: AppColors.coralSoft,
      onTertiaryContainer: AppColors.ink,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerLowest: AppColors.paper,
      surfaceContainerLow: AppColors.cream,
      surfaceContainer: const Color(0xFFF8F5ED),
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.line,
      outlineVariant: const Color(0xFFECE7DB),
      error: AppColors.danger,
      onError: AppColors.paper,
    );

    final textTheme = TextTheme(
      displayLarge: _text(size: 60, weight: FontWeight.w800, height: 1.02, letterSpacing: -2.8),
      displayMedium: _text(size: 48, weight: FontWeight.w800, height: 1.05, letterSpacing: -2.1),
      displaySmall: _text(size: 38, weight: FontWeight.w800, height: 1.08, letterSpacing: -1.4),
      headlineLarge: _text(size: 30, weight: FontWeight.w800, height: 1.15, letterSpacing: -0.9),
      headlineMedium: _text(size: 25, weight: FontWeight.w700, height: 1.2, letterSpacing: -0.5),
      headlineSmall: _text(size: 21, weight: FontWeight.w700, height: 1.25, letterSpacing: -0.3),
      titleLarge: _text(size: 19, weight: FontWeight.w700, height: 1.3),
      titleMedium: _text(size: 16, weight: FontWeight.w700, height: 1.35),
      titleSmall: _text(size: 14, weight: FontWeight.w700, height: 1.3),
      bodyLarge: _text(size: 16, weight: FontWeight.w500, height: 1.55),
      bodyMedium: _text(size: 14, weight: FontWeight.w500, height: 1.55),
      bodySmall: _text(size: 12, weight: FontWeight.w500, height: 1.45, color: AppColors.muted),
      labelLarge: _text(size: 13.5, weight: FontWeight.w700, height: 1.2, letterSpacing: 0.1),
      labelMedium: _text(size: 12, weight: FontWeight.w700, height: 1.2, letterSpacing: 0.2),
      labelSmall: _text(size: 10.5, weight: FontWeight.w700, height: 1.2, letterSpacing: 1.4),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
      fontFamily: 'Manrope',
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.paper,
          disabledBackgroundColor: AppColors.line,
          disabledForegroundColor: AppColors.muted,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: rounded,
          textStyle: _text(size: 14, weight: FontWeight.w700, color: AppColors.paper),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: rounded,
          textStyle: _text(size: 14, weight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: _text(size: 13.5, weight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.paper,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: rounded,
          textStyle: _text(size: 14, weight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          highlightColor: AppColors.limeSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paper,
        hintStyle: _text(size: 14, weight: FontWeight.w500, color: AppColors.muted),
        labelStyle: _text(size: 13, weight: FontWeight.w600, color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.ink;
          return AppColors.paper;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.lime;
          return AppColors.line;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? AppColors.lime : AppColors.line;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: _text(size: 13.5, weight: FontWeight.w600, color: AppColors.paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: _text(size: 12, weight: FontWeight.w600, color: AppColors.paper),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.sage.withValues(alpha: 0.55)),
        thickness: WidgetStateProperty.all(5),
        radius: const Radius.circular(999),
      ),
    );
  }
}

extension ThemeContext on BuildContext {
  TextTheme get texts => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isCompact => MediaQuery.sizeOf(this).width < 760;
  bool get isMedium => MediaQuery.sizeOf(this).width < 1100;
}
