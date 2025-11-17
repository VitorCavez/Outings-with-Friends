// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color success;
  final Color warning;
  final Color info;
  final Gradient primaryGradient;

  const BrandColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.primaryGradient,
  });

  @override
  BrandColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Gradient? primaryGradient,
  }) {
    return BrandColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      primaryGradient: primaryGradient ?? this.primaryGradient,
    );
  }

  @override
  ThemeExtension<BrandColors> lerp(
    ThemeExtension<BrandColors>? other,
    double t,
  ) {
    if (other is! BrandColors) return this;
    final a = primaryGradient as LinearGradient;
    final b = other.primaryGradient as LinearGradient;
    return BrandColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      primaryGradient: LinearGradient(
        begin: a.begin,
        end: a.end,
        colors: [
          Color.lerp(a.colors.first, b.colors.first, t)!,
          Color.lerp(a.colors.last, b.colors.last, t)!,
        ],
      ),
    );
  }
}

class AppTheme {
  static const _seed = Color(0xFF2363F5);
  static const _secondary = Color(0xFF20C997);
  static const _tertiary = Color(0xFFFFB703);
  static const _error = Color(0xFFE53935);
  static const _surfaceLight = Color(0xFFF7F9FC);
  static const _surfaceDark = Color(0xFF0E1422);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.light,
        secondary: _secondary,
        tertiary: _tertiary,
        error: _error,
        surface: _surfaceLight,
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme)
        .apply(
          bodyColor: base.colorScheme.onSurface,
          displayColor: base.colorScheme.onSurface,
        )
        .copyWith(
          headlineLarge: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            height: 1.15,
          ),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600),
          labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
          bodyMedium: GoogleFonts.inter(),
        );

    final brand = const BrandColors(
      success: Color(0xFF2E7D32),
      warning: Color(0xFFF59E0B),
      info: Color(0xFF0284C7),
      primaryGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2563EB), Color(0xFF22C55E)],
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: base.colorScheme.surface,
        foregroundColor: base.colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: base.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        toolbarTextStyle: textTheme.titleMedium?.copyWith(
          color: base.colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: base.colorScheme.surface,
        surfaceTintColor: base.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        textColor: base.colorScheme.onSurface,
        iconColor: base.colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: base.colorScheme.primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: base.colorScheme.outlineVariant),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: base.colorScheme.onSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: base.colorScheme.primary,
        unselectedLabelColor: base.colorScheme.onSurface.withValues(alpha: .6),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: base.colorScheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: base.colorScheme.onSurfaceVariant),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: base.colorScheme.primary,
        unselectedItemColor: base.colorScheme.onSurfaceVariant,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(base.colorScheme.surface),
          surfaceTintColor: WidgetStatePropertyAll(base.colorScheme.surface),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      extensions: [brand],
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
        secondary: _secondary,
        tertiary: _tertiary,
        error: _error,
        surface: _surfaceDark,
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme)
        .apply(
          bodyColor: base.colorScheme.onSurface,
          displayColor: base.colorScheme.onSurface,
        )
        .copyWith(
          headlineLarge: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            height: 1.15,
          ),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600),
          labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
          bodyMedium: GoogleFonts.inter(),
        );

    final brand = const BrandColors(
      success: Color(0xFF58D26F),
      warning: Color(0xFFFBBF24),
      info: Color(0xFF38BDF8),
      primaryGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3B82F6), Color(0xFF34D399)],
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: _surfaceDark,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: base.colorScheme.surface,
        foregroundColor: base.colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: base.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        toolbarTextStyle: textTheme.titleMedium?.copyWith(
          color: base.colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: base.colorScheme.surface,
        surfaceTintColor: base.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        textColor: base.colorScheme.onSurface,
        iconColor: base.colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: base.colorScheme.primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: base.colorScheme.outlineVariant),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: base.colorScheme.onSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: base.colorScheme.primary,
        unselectedLabelColor: base.colorScheme.onSurface.withValues(alpha: .7),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: base.colorScheme.primary.withValues(alpha: 0.20),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: base.colorScheme.onSurfaceVariant),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: base.colorScheme.primary,
        unselectedItemColor: base.colorScheme.onSurfaceVariant,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(base.colorScheme.surface),
          surfaceTintColor: WidgetStatePropertyAll(base.colorScheme.surface),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      extensions: [brand],
    );
  }
}
