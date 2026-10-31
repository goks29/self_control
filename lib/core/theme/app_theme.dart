import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

abstract final class AppTheme {
  static TextStyle displayTimer({Color color = AppColors.darkGreen}) =>
      GoogleFonts.workSans(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: color,
      );

  static TextStyle displayMetric({Color color = AppColors.darkGreen}) =>
      GoogleFonts.workSans(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.workSansTextTheme();

    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.darkGreen,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: AppColors.darkGreen,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.darkGreen,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.darkGreen,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.darkGreen,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkGreen,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.darkGreen,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.darkGreen,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.darkGreen,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: AppColors.darkGreen,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.darkGreenMuted,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.darkGreen,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.darkGreen,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.darkGreenMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.cream,
      primaryColor: AppColors.darkGreen,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.darkGreen,
        onPrimary: AppColors.cream,
        primaryContainer: AppColors.peach,
        onPrimaryContainer: AppColors.darkGreen,
        secondary: AppColors.brown,
        onSecondary: AppColors.white,
        secondaryContainer: AppColors.peach,
        onSecondaryContainer: AppColors.darkGreen,
        surface: AppColors.cream,
        onSurface: AppColors.darkGreen,
        error: AppColors.error,
        onError: AppColors.onError,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.cream,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.cream,
        ),
        iconTheme: const IconThemeData(color: AppColors.cream),
      ),
      cardTheme: CardThemeData(
        color: AppColors.peach,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brown,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkGreen,
          side: const BorderSide(color: AppColors.darkGreen, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.darkGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: textTheme.titleSmall,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.darkGreenMuted,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.error,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.modalRadius),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.cream,
        selectedItemColor: AppColors.brown,
        unselectedItemColor: AppColors.darkGreenMuted,
        selectedLabelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: textTheme.labelMedium,
        elevation: 4,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.brown;
          }
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(AppColors.white),
        side: const BorderSide(color: AppColors.darkGreen, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.peach,
        selectedColor: AppColors.brown,
        labelStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.darkGreen,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        side: BorderSide.none,
      ),
    );
  }
}
