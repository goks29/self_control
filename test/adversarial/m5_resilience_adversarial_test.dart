import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/repositories/activity_log_repository_impl.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';
import 'package:self_control/presentation/widgets/revoked_permission_banner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('Milestone 5 Adversarial Stress Tests: Revoked Permission Lifecycle', () {
    testWidgets('banner absent when accessibility service is enabled', (tester) async {
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
      expect(find.text('Izin Aksesibilitas Dicabut'), findsNothing);
    });

    testWidgets('banner displayed with warning text and fix button when disabled', (tester) async {
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
      expect(
        find.text('Layanan pemblokiran nonaktif. Aktifkan kembali agar perlindungan fokus berjalan.'),
        findsOneWidget,
      );
      expect(find.text('Aktifkan'), findsOneWidget);

      await tester.tap(find.text('Aktifkan'));
      await tester.pumpAndSettle();

      expect(platform.openSettingsCalled, isTrue);
    });

    testWidgets('resuming from background updates banner state dynamically without timer loops', (tester) async {
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

      platform.accessibilityStatus = 'disabled';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(RevokedPermissionBanner), findsOneWidget);
      expect(find.text('Izin Aksesibilitas Dicabut'), findsOneWidget);

      platform.accessibilityStatus = 'enabled';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(RevokedPermissionBanner), findsNothing);
    });
  });

  group('Milestone 5 Adversarial Stress Tests: Structured Outcome Logging Stream', () {
    testWidgets('native pending logs drained, mapped to app entities, and stored in repository', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository([
        BlockedApp(
          id: 42,
          packageName: 'com.instagram.android',
          appName: 'Instagram',
          isSelected: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');

      platform.pendingActivityLogs = [
        {
          'packageName': 'com.instagram.android',
          'outcome': ActivityLog.outcomeConfirmed,
          'details': 'lock_screen_launched',
          'timestampMs': 1700000000000,
        },
        {
          'packageName': 'com.unmapped.app',
          'outcome': ActivityLog.outcomeFailed,
          'details': 'ActivityNotFoundException',
          'timestampMs': 1700000005000,
        },
        {
          'packageName': 'com.test.attempt',
          'outcome': ActivityLog.outcomeAttempted,
          'details': null,
          'timestampMs': 1700000010000,
        },
        {
          'packageName': 'com.test.notreq',
          'outcome': ActivityLog.outcomeNotRequired,
          'details': 'whitelist',
          'timestampMs': 1700000015000,
        },
      ];

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

      expect(logRepo.logs.length, 4);

      final instagramLog = logRepo.logs.firstWhere((l) => l.packageNameSnapshot == 'com.instagram.android');
      expect(instagramLog.appId, 42);
      expect(instagramLog.appNameSnapshot, 'Instagram');
      expect(instagramLog.outcome, ActivityLog.outcomeConfirmed);
      expect(instagramLog.details, 'lock_screen_launched');

      final unmappedLog = logRepo.logs.firstWhere((l) => l.packageNameSnapshot == 'com.unmapped.app');
      expect(unmappedLog.appId, isNull);
      expect(unmappedLog.appNameSnapshot, 'com.unmapped.app');
      expect(unmappedLog.outcome, ActivityLog.outcomeFailed);
      expect(unmappedLog.details, 'ActivityNotFoundException');

      final attemptedLog = logRepo.logs.firstWhere((l) => l.packageNameSnapshot == 'com.test.attempt');
      expect(attemptedLog.outcome, ActivityLog.outcomeAttempted);

      final notReqLog = logRepo.logs.firstWhere((l) => l.packageNameSnapshot == 'com.test.notreq');
      expect(notReqLog.outcome, ActivityLog.outcomeNotRequired);

      expect(platform.pendingActivityLogs.isEmpty, isTrue);

      platform.pendingActivityLogs = [
        {
          'packageName': 'com.resume.app',
          'outcome': ActivityLog.outcomeConfirmed,
          'details': 'resumed_drain',
          'timestampMs': 1700000020000,
        },
      ];

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(logRepo.logs.length, 5);
      expect(logRepo.logs.last.packageNameSnapshot, 'com.resume.app');
      expect(platform.pendingActivityLogs.isEmpty, isTrue);
    });

    test('SQLite ActivityLogRepository getOutcomeCounts and getAttemptCountsByPackage tallies correctly', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: AppDatabase.dbVersion,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE ${AppDatabase.tableActivityLogs} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              app_id INTEGER,
              session_id INTEGER,
              package_name_snapshot TEXT NOT NULL,
              app_name_snapshot TEXT NOT NULL,
              event_type TEXT NOT NULL,
              outcome TEXT NOT NULL DEFAULT 'confirmed',
              details TEXT,
              attempted_at INTEGER NOT NULL
            );
          ''');
        },
      );

      final repo = ActivityLogRepositoryImpl(db: db);

      for (int i = 0; i < 4; i++) {
        await repo.logEvent(
          ActivityLog(
            packageNameSnapshot: 'com.tiktok.android',
            appNameSnapshot: 'TikTok',
            eventType: ActivityLog.eventBlockedAttempt,
            outcome: ActivityLog.outcomeConfirmed,
            attemptedAt: DateTime.fromMillisecondsSinceEpoch(1000 + i),
          ),
        );
      }

      for (int i = 0; i < 3; i++) {
        await repo.logEvent(
          ActivityLog(
            packageNameSnapshot: 'com.tiktok.android',
            appNameSnapshot: 'TikTok',
            eventType: ActivityLog.eventBlockedAttempt,
            outcome: ActivityLog.outcomeAttempted,
            attemptedAt: DateTime.fromMillisecondsSinceEpoch(2000 + i),
          ),
        );
      }

      for (int i = 0; i < 2; i++) {
        await repo.logEvent(
          ActivityLog(
            packageNameSnapshot: 'com.instagram.android',
            appNameSnapshot: 'Instagram',
            eventType: ActivityLog.eventBlockedAttempt,
            outcome: ActivityLog.outcomeFailed,
            details: 'launch_failed',
            attemptedAt: DateTime.fromMillisecondsSinceEpoch(3000 + i),
          ),
        );
      }

      await repo.logEvent(
        ActivityLog(
          packageNameSnapshot: 'com.browser.app',
          appNameSnapshot: 'Browser',
          eventType: ActivityLog.eventBlockedAttempt,
          outcome: ActivityLog.outcomeNotRequired,
          attemptedAt: DateTime.fromMillisecondsSinceEpoch(4000),
        ),
      );

      final outcomeCounts = await repo.getOutcomeCounts();
      expect(outcomeCounts[ActivityLog.outcomeConfirmed], 4);
      expect(outcomeCounts[ActivityLog.outcomeAttempted], 3);
      expect(outcomeCounts[ActivityLog.outcomeFailed], 2);
      expect(outcomeCounts[ActivityLog.outcomeNotRequired], 1);

      final confirmedPackageCounts = await repo.getAttemptCountsByPackage(outcome: ActivityLog.outcomeConfirmed);
      expect(confirmedPackageCounts['com.tiktok.android'], 4);
      expect(confirmedPackageCounts.containsKey('com.instagram.android'), isFalse);

      final allPackageCounts = await repo.getAttemptCountsByPackage(outcome: null);
      expect(allPackageCounts['com.tiktok.android'], 7);
      expect(allPackageCounts['com.instagram.android'], 2);
      expect(allPackageCounts['com.browser.app'], 1);

      await db.close();
    });
  });
}
