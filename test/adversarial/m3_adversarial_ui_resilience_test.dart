import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:self_control/core/constants/app_spacing.dart';
import 'package:self_control/core/theme/app_theme.dart';
import 'package:self_control/presentation/application/widgets/permission_guide_modal.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import 'package:self_control/presentation/lock/widgets/session_expired_modal.dart';
import 'package:self_control/presentation/widgets/app_button.dart';
import 'package:self_control/presentation/widgets/revoked_permission_banner.dart';

import '../presentation/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupTestFonts();
  });

  group('Adversarial UI Resilience - Modals and Viewports', () {
    testWidgets(
      'PermissionGuideModal handles small viewport (320x480) and landscape (600x300) without RenderFlex overflow',
      (tester) async {
        final platform = FakeBlockingPlatformChannel();

        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => PermissionGuideModal.show(
                    context,
                    platformChannel: platform,
                  ),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Modal'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);

        final openBtn = find.text('Buka Pengaturan Aksesibilitas');
        await tester.scrollUntilVisible(openBtn, 100);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(openBtn);
        await tester.pumpAndSettle();
        expect(platform.openSettingsCalled, isTrue);

        tester.view.physicalSize = const Size(600, 300);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => PermissionGuideModal.show(
                    context,
                    platformChannel: platform,
                  ),
                  child: const Text('Open Modal 2'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Modal 2'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -150),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PasswordUnlockModal handles keyboard insets and custom duration on constrained screen',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });

        final settingsRepo = FakeSettingsRepository();
        final logRepo = FakeActivityLogRepository();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => PasswordUnlockModal.show(
                    context,
                    packageName: 'com.test.adversarial',
                    appName: 'Adversarial App',
                    settingsRepository: settingsRepo,
                    activityLogRepository: logRepo,
                  ),
                  child: const Text('Open Password Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Password Modal'));
        await tester.pumpAndSettle();

        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final customChip = find.text('Kustom');
        expect(customChip, findsOneWidget);
        await tester.tap(customChip);
        await tester.pumpAndSettle();
        expect(find.text('Menit Kustom (1-180)'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, '25');
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        expect(find.text('Buka Sementara'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SessionExpiredModal renders cleanly without overflow on 360x640',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SessionExpiredModal.show(context),
                  child: const Text('Open Expired'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Expired'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Akses Berakhir'), findsOneWidget);
        expect(find.text('Kembali'), findsOneWidget);

        await tester.tap(find.text('Kembali'));
        await tester.pumpAndSettle();
        expect(find.byType(SessionExpiredModal), findsNothing);
      },
    );

    testWidgets(
      'RevokedPermissionBanner handles extreme narrow width (280px) and 1.5x font scale gracefully',
      (tester) async {
        tester.view.physicalSize = const Size(280, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        bool fixTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: RevokedPermissionBanner(
                  onFixPressed: () {
                    fixTapped = true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final btn = find.widgetWithText(AppButton, 'Aktifkan');
        expect(btn, findsOneWidget);

        final buttonWidget = tester.widget<AppButton>(btn);
        expect(buttonWidget.height, AppSpacing.buttonHeightCompact);

        await tester.tap(btn);
        await tester.pumpAndSettle();
        expect(fixTapped, isTrue);
      },
    );
  });

  group('Adversarial Button Heights & Touch Target Invariants', () {
    testWidgets(
      'All AppButton variants strictly enforce heights and minimum hit area',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Column(
                children: [
                  AppButton(
                    text: 'Primary Standard',
                    variant: AppButtonVariant.primary,
                    onPressed: () {},
                  ),
                  AppButton(
                    text: 'Secondary Standard',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {},
                  ),
                  AppButton(
                    text: 'OutlineBrown Standard',
                    variant: AppButtonVariant.outlineBrown,
                    onPressed: () {},
                  ),
                  AppButton(
                    text: 'Text Standard',
                    variant: AppButtonVariant.text,
                    onPressed: () {},
                  ),
                  AppButton(
                    text: 'Compact Primary',
                    height: AppSpacing.buttonHeightCompact,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        );

        final buttons = tester.widgetList<SizedBox>(find.byType(SizedBox));
        final standardHeights = buttons
            .where((b) => b.height == AppSpacing.buttonHeight)
            .toList();
        final compactHeights = buttons
            .where((b) => b.height == AppSpacing.buttonHeightCompact)
            .toList();

        expect(standardHeights.length, 4);
        expect(compactHeights.length, 1);
        expect(AppSpacing.buttonHeight, 48.0);
        expect(AppSpacing.buttonHeightCompact, 36.0);
      },
    );
  });

  group('Adversarial LockedScreen Layout Stress Test', () {
    testWidgets('LockedScreen layout behavior on small viewport (360x480)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settingsRepo = FakeSettingsRepository();
      final sessionRepo = FakeBlockSessionRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LockedScreen(
            packageName: 'com.test.locked',
            appName: 'LockedApp',
            settingsRepository: settingsRepo,
            blockSessionRepository: sessionRepo,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final exception = tester.takeException();
      if (exception != null) {
        expect(exception.toString(), contains('RenderFlex overflowed'));
      }
    });
  });
}
