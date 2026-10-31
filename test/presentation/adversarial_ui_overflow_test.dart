import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/theme/app_theme.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/presentation/application/application_selection_screen.dart';
import 'package:self_control/presentation/application/widgets/permission_guide_modal.dart';
import 'package:self_control/presentation/home/dashboard_screen.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import 'package:self_control/presentation/lock/widgets/session_expired_modal.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import 'package:self_control/presentation/widgets/revoked_permission_banner.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('Adversarial UI & Screen Resilience Tests', () {
    testWidgets('DashboardScreen renders without overflow on 320x480 with long names and data', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final logRepo = FakeActivityLogRepository();
      for (int i = 0; i < 15; i++) {
        await logRepo.logEvent(
          ActivityLog(
            appId: i + 1,
            packageNameSnapshot: 'com.example.superlongpackagenamethatexceedsnormaldisplaylimits$i',
            appNameSnapshot: 'Super Extremely Exaggerated Long Application Title Number $i For Stress Testing',
            eventType: ActivityLog.eventBlockedAttempt,
            outcome: ActivityLog.outcomeConfirmed,
            attemptedAt: DateTime.now().subtract(Duration(minutes: i * 15)),
          ),
        );
      }
      await logRepo.logEvent(
        ActivityLog(
          appId: 99,
          packageNameSnapshot: 'com.example.failed',
          appNameSnapshot: 'Failed App',
          eventType: ActivityLog.eventBlockedAttempt,
          outcome: ActivityLog.outcomeFailed,
          attemptedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: DashboardScreen(
            activityLogRepository: logRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(DashboardScreen), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DashboardScreen empty state renders without overflow on 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: DashboardScreen(
            activityLogRepository: logRepo,
            onNavigateToApplications: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Belum Ada Aktivitas Blokir'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ApplicationSelectionScreen renders without overflow on 320x480 with long names', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apps = List.generate(
        10,
        (i) => BlockedApp(
          id: i + 1,
          packageName: 'com.corporation.subdivision.superlongpackagename.identifier$i',
          appName: 'Hyper Extended Application Title Number $i With Multiple Words Exceeding Standard Layout',
          isSelected: i % 2 == 0,
          createdAt: DateTime.now(),
        ),
      );
      final appRepo = FakeBlockedAppRepository(apps);
      final channel = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ApplicationSelectionScreen(
            blockedAppRepository: appRepo,
            platformChannel: channel,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(ApplicationSelectionScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hyper');
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Pilih Semua'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsScreen renders and scrolls without overflow on 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'custom_lock_message': 'Tetap fokus pada tujuan besar dan jangan pernah tergoda oleh distraksi instan kapan pun dan di mana pun.',
          'waiting_duration_seconds': '300',
          'default_unlock_duration_seconds': '600',
        },
      );
      final fakeDb = FakeAppDatabase();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: SettingsScreen(
            settingsRepository: settingsRepo,
            appDatabase: fakeDb,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('RevokedPermissionBanner renders without overflow on 320x480', (tester) async {
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
            body: RevokedPermissionBanner(
              onFixPressed: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Izin Aksesibilitas Dicabut'), findsOneWidget);
    });

    testWidgets('MainScaffold renders with banner without overflow on 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final channel = FakeBlockingPlatformChannel(accessibilityStatus: 'disabled');
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final unlockRepo = FakeTemporaryUnlockRepository();

      FlutterErrorDetails? errorDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MainScaffold(
            platformChannel: channel,
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            temporaryUnlockRepository: unlockRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      if (errorDetails != null) {
        debugPrint(errorDetails.toString());
      }
      expect(errorDetails, isNull);
      expect(find.byType(RevokedPermissionBanner), findsOneWidget);
    });

    testWidgets('PermissionGuideModal renders without overflow on 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final channel = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => PermissionGuideModal.show(ctx, platformChannel: channel),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Aktivasi Layanan Aksesibilitas'), findsOneWidget);

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SessionExpiredModal renders without overflow on 320x480', (tester) async {
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
              builder: (ctx) => ElevatedButton(
                onPressed: () => SessionExpiredModal.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Akses Berakhir'), findsOneWidget);
    });

    testWidgets('PasswordUnlockModal with custom duration renders without overflow on 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settingsRepo = FakeSettingsRepository(expectedPassword: 'secret');
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final channel = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => PasswordUnlockModal.show(
                  ctx,
                  packageName: 'com.test.app',
                  appName: 'Test Application',
                  settingsRepository: settingsRepo,
                  temporaryUnlockRepository: unlockRepo,
                  activityLogRepository: logRepo,
                  blockedAppRepository: appRepo,
                  platformChannel: channel,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Kustom'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('LockedScreen under extreme strings and 320x480 constraints', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const extremeAppName = 'Extremely Long Application Name That Spans Multiple Lines On Constrained Screens';
      const extremeQuote = 'Disiplin adalah jembatan antara cita-cita dan pencapaian. Jangan biarkan keinginan sesaat mengorbankan impian masa depanmu.';
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'custom_lock_message': extremeQuote,
          'waiting_duration_seconds': '300',
        },
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LockedScreen(
            appName: extremeAppName,
            packageName: 'com.extremely.long.package.name.identifier.stress.test',
            startAtEpochMs: now,
            endAtEpochMs: now + 300000,
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text(extremeAppName), findsOneWidget);
    });
  });
}
