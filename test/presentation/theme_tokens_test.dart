import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/constants/app_colors.dart';
import 'package:self_control/core/constants/app_spacing.dart';
import 'package:self_control/core/theme/app_theme.dart';
import 'package:self_control/presentation/widgets/app_button.dart';
import 'package:self_control/presentation/widgets/app_card.dart';
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

  group('AppSpacing Design Tokens', () {
    test('defines correct spacing scale, dimensions, and layout paddings', () {
      expect(AppSpacing.xs, 4.0);
      expect(AppSpacing.sm, 8.0);
      expect(AppSpacing.md, 12.0);
      expect(AppSpacing.lg, 16.0);
      expect(AppSpacing.xl, 20.0);
      expect(AppSpacing.xxl, 24.0);
      expect(AppSpacing.xxxl, 32.0);

      expect(AppSpacing.buttonHeight, 48.0);
      expect(AppSpacing.buttonHeightCompact, 36.0);
      expect(AppSpacing.buttonRadius, 8.0);
      expect(AppSpacing.cardRadius, 12.0);
      expect(AppSpacing.modalRadius, 16.0);

      expect(AppSpacing.radiusXs, 4.0);
      expect(AppSpacing.radiusSm, 8.0);
      expect(AppSpacing.radiusMd, 12.0);
      expect(AppSpacing.radiusLg, 16.0);

      expect(AppSpacing.screenMargin, 16.0);
      expect(AppSpacing.screenPadding, const EdgeInsets.all(16.0));
      expect(AppSpacing.cardPadding, const EdgeInsets.all(16.0));
      expect(AppSpacing.cardMargin, const EdgeInsets.only(bottom: 12.0));
      expect(AppSpacing.sheetPadding, const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 32.0));
      expect(AppSpacing.dialogPadding, const EdgeInsets.all(24.0));
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

  group('AppButton & AppCard Token Defaults', () {
    testWidgets('AppButton defaults to AppSpacing buttonHeight and buttonRadius', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppButton(
              text: 'Simpan',
              onPressed: () {},
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.height, AppSpacing.buttonHeight);

      final elevatedButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final shape = elevatedButton.style?.shape?.resolve({}) as RoundedRectangleBorder?;
      expect(shape?.borderRadius, BorderRadius.circular(AppSpacing.buttonRadius));
    });

    testWidgets('AppCard defaults to AppSpacing cardPadding and cardRadius', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppCard(child: Text('Konten')),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.padding, AppSpacing.cardPadding);

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppSpacing.cardRadius));
    });
  });
}
