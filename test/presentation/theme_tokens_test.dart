import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/constants/app_colors.dart';
import 'package:self_control/core/theme/app_theme.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('AppColors Design Tokens', () {
    test('defines correct 4-color palette hex codes', () {
      expect(AppColors.darkGreen, const Color(0xFF09251C));
      expect(AppColors.brown, const Color(0xFFA55704));
      expect(AppColors.peach, const Color(0xFFF3D2AF));
      expect(AppColors.cream, const Color(0xFFF8EADC));
      expect(AppColors.white, const Color(0xFFFFFFFF));
      expect(AppColors.error, const Color(0xFFBA1A1A));
    });
  });

  group('AppTheme Configuration', () {
    testWidgets('lightTheme has Material 3, Cream canvas, and Dark Green primary', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Text('Hello')),
        ),
      );

      final theme = AppTheme.lightTheme;
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, AppColors.cream);
      expect(theme.primaryColor, AppColors.darkGreen);
      expect(theme.colorScheme.primary, AppColors.darkGreen);
      expect(theme.colorScheme.secondary, AppColors.brown);
      expect(theme.appBarTheme.backgroundColor, AppColors.darkGreen);
      expect(theme.appBarTheme.foregroundColor, AppColors.cream);
    });

    testWidgets('lightTheme textTheme uses Work Sans family with Dark Green color', (tester) async {
      final theme = AppTheme.lightTheme;
      expect(theme.textTheme.headlineLarge?.color, AppColors.darkGreen);
      expect(theme.textTheme.titleMedium?.color, AppColors.darkGreen);
      expect(theme.textTheme.bodyMedium?.color, AppColors.darkGreen);
      expect(theme.textTheme.bodyMedium?.fontFamily, contains('WorkSans'));
    });
  });
}
