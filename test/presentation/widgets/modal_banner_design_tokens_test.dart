import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/constants/app_colors.dart';
import 'package:self_control/core/constants/app_spacing.dart';
import 'package:self_control/core/theme/app_theme.dart';
import 'package:self_control/presentation/application/widgets/permission_guide_modal.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import 'package:self_control/presentation/lock/widgets/session_expired_modal.dart';
import 'package:self_control/presentation/widgets/app_button.dart';
import 'package:self_control/presentation/widgets/revoked_permission_banner.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('PasswordUnlockModal Design Tokens', () {
    testWidgets('conforms to sheetPadding, radius, textTheme, and button height', (tester) async {
      final settingsRepo = FakeSettingsRepository();
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'TestApp',
              packageName: 'com.test.app',
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PasswordUnlockModal),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.padding, AppSpacing.sheetPadding);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.cream);
      expect(
        decoration.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(AppSpacing.xxl)),
      );

      final title = tester.widget<Text>(find.text('Buka Akses Sementara'));
      expect(title.style?.fontSize, 20);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(title.style?.color, AppColors.darkGreen);

      final subtitle = tester.widget<Text>(
        find.text('Waktu tunggu selesai. Masukkan password Anda untuk membuka akses sementara.'),
      );
      expect(subtitle.style?.fontSize, 14);
      expect(subtitle.style?.color, AppColors.darkGreenMuted);

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Buka Sementara'),
      );
      expect(button.height, AppSpacing.buttonHeight);
    });
  });

  group('PermissionGuideModal Design Tokens', () {
    testWidgets('conforms to sheetPadding, textTheme, and step spacing', (tester) async {
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PermissionGuideModal(platformChannel: platform),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PermissionGuideModal),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.padding, AppSpacing.sheetPadding);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.cream);
      expect(
        decoration.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(AppSpacing.xxl)),
      );

      final title = tester.widget<Text>(find.text('Aktivasi Layanan Aksesibilitas'));
      expect(title.style?.fontSize, 18);
      expect(title.style?.fontWeight, FontWeight.w700);

      final desc = tester.widget<Text>(
        find.text(
          'Aplikasi Self-Control memerlukan izin Layanan Aksesibilitas untuk mendeteksi kapan aplikasi yang dibatasi dibuka, sehingga pemblokiran dapat berjalan secara otomatis tanpa menguras baterai.',
        ),
      );
      expect(desc.style?.fontSize, 14);

      final step1 = tester.widget<Text>(find.text('Tekan tombol "Buka Pengaturan" di bawah.'));
      expect(step1.style?.fontSize, 14);

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Buka Pengaturan Aksesibilitas'),
      );
      expect(button.height, AppSpacing.buttonHeight);
    });
  });

  group('SessionExpiredModal Design Tokens', () {
    testWidgets('conforms to dialogPadding, modalRadius, textTheme, and button height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SessionExpiredModal.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, AppColors.cream);
      final shape = dialog.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(AppSpacing.modalRadius));

      final padding = tester.widget<Padding>(
        find.ancestor(
          of: find.byType(Column),
          matching: find.byType(Padding),
        ).first,
      );
      expect(padding.padding, AppSpacing.dialogPadding);

      final title = tester.widget<Text>(find.text('Akses Berakhir'));
      expect(title.style?.fontSize, 20);
      expect(title.style?.fontWeight, FontWeight.w700);

      final desc = tester.widget<Text>(
        find.text('Waktu akses sementara telah berakhir. Aplikasi kembali dibatasi.'),
      );
      expect(desc.style?.fontSize, 14);

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Kembali'),
      );
      expect(button.height, AppSpacing.buttonHeight);
    });
  });

  group('RevokedPermissionBanner Design Tokens', () {
    testWidgets('conforms to container padding, textTheme, and compact button height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: RevokedPermissionBanner(
              onFixPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(RevokedPermissionBanner),
          matching: find.byType(Container),
        ).first,
      );
      expect(
        container.padding,
        const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      );

      final title = tester.widget<Text>(find.text('Izin Aksesibilitas Dicabut'));
      expect(title.style?.fontSize, 14);
      expect(title.style?.fontWeight, FontWeight.w700);

      final desc = tester.widget<Text>(
        find.text(
          'Layanan pemblokiran nonaktif. Aktifkan kembali agar perlindungan fokus berjalan.',
        ),
      );
      expect(desc.style?.fontSize, 12);

      final button = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Aktifkan'));
      expect(button.height, AppSpacing.buttonHeightCompact);
    });
  });
}
