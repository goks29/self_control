import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import 'package:self_control/presentation/widgets/revoked_permission_banner.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('MainScaffold Navigation Shell', () {
    testWidgets('renders BottomNavigationBar and switches between Dashboard and Apps', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Beranda'), findsWidgets);
      expect(find.text('Aplikasi'), findsWidgets);

      await tester.tap(find.text('Aplikasi').last);
      await tester.pumpAndSettle();

      expect(find.text('Pilih Aplikasi'), findsOneWidget);
    });

    testWidgets('opens Drawer and navigates to Settings', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ScaffoldState state = tester.firstState(find.byType(Scaffold));
      state.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Self-Control'), findsOneWidget);
      expect(find.text('Fokus & Disiplin Digital'), findsOneWidget);
      expect(find.text('Pengaturan'), findsOneWidget);

      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('shows RevokedPermissionBanner when accessibility service is disabled', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel(accessibilityStatus: 'disabled');

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RevokedPermissionBanner), findsOneWidget);
      expect(find.text('Izin Aksesibilitas Dicabut'), findsOneWidget);

      await tester.tap(find.text('Aktifkan'));
      await tester.pumpAndSettle();

      expect(platform.openSettingsCalled, isTrue);
    });

    testWidgets('hides RevokedPermissionBanner when accessibility service is enabled', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RevokedPermissionBanner), findsNothing);
    });

    testWidgets('drains pending activity logs on launch and inserts into repository', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final unlockRepo = FakeTemporaryUnlockRepository();
      final platform = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');
      platform.pendingActivityLogs = [
        {
          'packageName': 'com.tiktok.android',
          'outcome': 'confirmed',
          'details': 'lock_screen_launched',
          'timestampMs': 1700000000000,
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            temporaryUnlockRepository: unlockRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(logRepo.logs.length, 1);
      expect(logRepo.logs.first.packageNameSnapshot, 'com.tiktok.android');
      expect(logRepo.logs.first.outcome, 'confirmed');
      expect(logRepo.logs.first.details, 'lock_screen_launched');
      expect(platform.pendingActivityLogs.isEmpty, isTrue);
    });
  });
}
