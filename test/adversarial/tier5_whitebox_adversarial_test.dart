import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/core/theme/app_theme.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/models/block_session.dart';
import 'package:self_control/data/models/temporary_unlock.dart';
import 'package:self_control/presentation/application/application_selection_screen.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';

import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(BlockingPlatformChannel.channelName),
          (MethodCall call) async {
            switch (call.method) {
              case 'getBlockingCapability':
                return {
                  'mode': 'standard',
                  'serviceStatus': 'disabled',
                  'limitations': <String>[],
                };
              case 'getAccessibilityStatus':
                return 'disabled';
              case 'openAccessibilitySettings':
                return true;
              case 'getInstalledApps':
                return <Map<String, dynamic>>[];
              case 'syncBlockedApps':
                return {'syncedCount': 0, 'status': 'success'};
              case 'syncTemporaryUnlock':
                return {'status': 'success'};
              case 'revokeTemporaryUnlock':
                return {'status': 'success'};
              case 'syncActiveSessions':
                return {'status': 'success'};
              case 'consumePendingBootEvents':
                return <int>[];
              default:
                return null;
            }
          },
        );
  });

  group(
    'Tier 5 Adversarial Focus 1: UI State Machine Transitions & Tamper Defense',
    () {
      testWidgets(
        'Rapid back button spam on LockedScreen does not dismiss barrier and calls pop safely',
        (tester) async {
          int popCallCount = 0;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (MethodCall call) async {
              if (call.method == 'SystemNavigator.pop') {
                popCallCount++;
              }
              return null;
            },
          );

          final settingsRepo = FakeSettingsRepository();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: LockedScreen(
                packageName: 'com.spam.target',
                appName: 'Target Spam App',
                settingsRepository: settingsRepo,
                autoOpenModal: false,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.byType(LockedScreen), findsOneWidget);

          for (int i = 0; i < 50; i++) {
            final handled = await tester.binding.handlePopRoute();
            expect(handled, isTrue);
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.byType(LockedScreen), findsOneWidget);
          expect(popCallCount, equals(50));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'Rapid tab switching between Dashboard and Application Selection maintains clean state',
        (tester) async {
          final logRepo = FakeActivityLogRepository();
          final appRepo = FakeBlockedAppRepository([
            BlockedApp(
              packageName: 'com.app.one',
              appName: 'App One',
              isSelected: true,
              createdAt: DateTime.now(),
            ),
          ]);
          final unlockRepo = FakeTemporaryUnlockRepository();
          final platform = FakeBlockingPlatformChannel(
            accessibilityStatus: 'enabled',
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: MainScaffold(
                activityLogRepository: logRepo,
                blockedAppRepository: appRepo,
                temporaryUnlockRepository: unlockRepo,
                platformChannel: platform,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          for (int i = 0; i < 20; i++) {
            await tester.tap(
              find.byIcon(
                i % 2 == 0 ? Icons.apps_outlined : Icons.dashboard_outlined,
              ),
            );
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 100));

          expect(tester.takeException(), isNull);
          expect(find.byType(MainScaffold), findsOneWidget);
        },
      );

      testWidgets(
        'Active countdown forward clock jump triggers anti-tamper penalty and logs event',
        (tester) async {
          final baseNow = 1700000000000;
          int simulatedNow = baseNow;
          final logRepo = FakeActivityLogRepository();
          final settingsRepo = FakeSettingsRepository();

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: LockedScreen(
                packageName: 'com.jump.target',
                appName: 'Forward Jump Target',
                startAtEpochMs: baseNow,
                endAtEpochMs: baseNow + 300000,
                settingsRepository: settingsRepo,
                activityLogRepository: logRepo,
                nowMsProvider: () => simulatedNow,
                autoOpenModal: false,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('05:00'), findsOneWidget);
          expect(
            logRepo.logs.where(
              (l) => l.eventType == ActivityLog.eventTamperingDetected,
            ),
            isEmpty,
          );

          simulatedNow = baseNow + 120000;
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 100));

          final tamperingLogs = logRepo.logs
              .where((l) => l.eventType == ActivityLog.eventTamperingDetected)
              .toList();
          expect(tamperingLogs.length, equals(1));
          expect(
            tamperingLogs.first.packageNameSnapshot,
            equals('com.jump.target'),
          );
          expect(find.text('05:00'), findsOneWidget);
        },
      );

      testWidgets(
        'Active countdown backward clock jump triggers anti-tamper penalty and logs event',
        (tester) async {
          final baseNow = 1700000000000;
          int simulatedNow = baseNow;
          final logRepo = FakeActivityLogRepository();
          final settingsRepo = FakeSettingsRepository();

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: LockedScreen(
                packageName: 'com.backward.target',
                appName: 'Backward Jump Target',
                startAtEpochMs: baseNow,
                endAtEpochMs: baseNow + 300000,
                settingsRepository: settingsRepo,
                activityLogRepository: logRepo,
                nowMsProvider: () => simulatedNow,
                autoOpenModal: false,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('05:00'), findsOneWidget);

          simulatedNow = baseNow - 60000;
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 100));

          final tamperingLogs = logRepo.logs
              .where((l) => l.eventType == ActivityLog.eventTamperingDetected)
              .toList();
          expect(tamperingLogs.length, equals(1));
          expect(
            tamperingLogs.first.packageNameSnapshot,
            equals('com.backward.target'),
          );
          expect(find.text('05:00'), findsOneWidget);
        },
      );

      testWidgets(
        'Rapid multi-tap on activate blocking does not cause concurrency race or crash',
        (tester) async {
          final appRepo = FakeBlockedAppRepository([
            BlockedApp(
              packageName: 'com.rapid.app',
              appName: 'Rapid App',
              isSelected: true,
              createdAt: DateTime.now(),
            ),
          ]);
          final platform = FakeBlockingPlatformChannel(
            accessibilityStatus: 'enabled',
            installedApps: [
              {'packageName': 'com.rapid.app', 'appName': 'Rapid App'},
            ],
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: ApplicationSelectionScreen(
                blockedAppRepository: appRepo,
                platformChannel: platform,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          for (int i = 0; i < 15; i++) {
            await tester.tap(find.text('Aktifkan Pemblokiran'));
            await tester.pump(const Duration(milliseconds: 10));
          }
          await tester.pump(const Duration(milliseconds: 100));

          expect(tester.takeException(), isNull);
          expect(platform.lastSyncedPackages, contains('com.rapid.app'));
        },
      );

      test('Corrupted database file on disk recovers gracefully on startup without crash', () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'startup_corrupt_harness_',
        );
        final dbPath = p.join(tempDir.path, 'startup_test.db');
        File(dbPath).writeAsStringSync('CORRUPT_BYTES_XYZ_JUNK_HEADER');

        final appDb = AppDatabase();
        final db = await appDb.initDatabase(
          customPath: dbPath,
          factory: databaseFactoryFfi,
          enableAutoRecovery: true,
        );

        expect(db.isOpen, isTrue);
        final integrity = await appDb.verifyIntegrity(full: true, targetDb: db);
        expect(integrity.isHealthy, isTrue);

        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
        );
        final names = tables.map((r) => r['name'] as String).toSet();
        expect(names, contains(AppDatabase.tableBlockedApps));
        expect(names, contains(AppDatabase.tableActivityLogs));

        await appDb.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
    },
  );

  group(
    'Tier 5 Adversarial Focus 2: Database Edge Cases & Concurrency Integrity',
    () {
      late AppDatabase appDb;
      late Database db;

      setUp(() async {
        appDb = AppDatabase();
        db = await appDb.initDatabase(
          customPath: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );
      });

      tearDown(() async {
        await appDb.close();
      });

      test(
        'Foreign key ON DELETE RESTRICT blocks app deletion when unlock exists',
        () async {
          final appId = await db.insert(AppDatabase.tableBlockedApps, {
            'package_name': 'com.restrict.target',
            'app_name': 'Restrict Target',
            'is_selected': 1,
            'created_at': 1000,
          });

          await db.insert(AppDatabase.tableTemporaryUnlocks, {
            'app_id': appId,
            'start_at': 1000,
            'end_at': 2000,
            'status': TemporaryUnlock.statusActive,
            'created_at': 1000,
          });

          expect(
            () async => await db.delete(
              AppDatabase.tableBlockedApps,
              where: 'id = ?',
              whereArgs: [appId],
            ),
            throwsA(isA<DatabaseException>()),
          );

          final appCheck = await db.query(
            AppDatabase.tableBlockedApps,
            where: 'id = ?',
            whereArgs: [appId],
          );
          expect(appCheck, isNotEmpty);
        },
      );

      test('Foreign key ON DELETE SET NULL on block_sessions sets foreign keys to NULL without deleting child rows', () async {
        final appId = await db.insert(AppDatabase.tableBlockedApps, {
          'package_name': 'com.setnull.target',
          'app_name': 'SetNull Target',
          'is_selected': 1,
          'created_at': 1000,
        });

        final sessionId = await db.insert(AppDatabase.tableBlockSessions, {
          'start_at': 1000,
          'end_at': 3000,
          'status': BlockSession.statusActive,
          'created_at': 1000,
        });

        final unlockId = await db.insert(AppDatabase.tableTemporaryUnlocks, {
          'app_id': appId,
          'session_id': sessionId,
          'start_at': 1000,
          'end_at': 2000,
          'status': TemporaryUnlock.statusActive,
          'created_at': 1000,
        });

        final logId = await db.insert(AppDatabase.tableActivityLogs, {
          'app_id': appId,
          'session_id': sessionId,
          'package_name_snapshot': 'com.setnull.target',
          'app_name_snapshot': 'SetNull Target',
          'event_type': ActivityLog.eventBlockedAttempt,
          'attempted_at': 1500,
        });

        final deletedSessions = await db.delete(
          AppDatabase.tableBlockSessions,
          where: 'id = ?',
          whereArgs: [sessionId],
        );
        expect(deletedSessions, equals(1));

        final unlockRows = await db.query(
          AppDatabase.tableTemporaryUnlocks,
          where: 'id = ?',
          whereArgs: [unlockId],
        );
        expect(unlockRows.length, equals(1));
        expect(unlockRows.first['session_id'], isNull);
        expect(unlockRows.first['app_id'], equals(appId));

        final logRows = await db.query(
          AppDatabase.tableActivityLogs,
          where: 'id = ?',
          whereArgs: [logId],
        );
        expect(logRows.length, equals(1));
        expect(logRows.first['session_id'], isNull);
        expect(logRows.first['app_id'], equals(appId));
        expect(
          logRows.first['package_name_snapshot'],
          equals('com.setnull.target'),
        );
      });

      test('Corrupt journal and wal files are safely backed up and -shm is deleted during recovery', () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'journal_wal_harness_',
        );
        final dbPath = p.join(tempDir.path, 'journal_test.db');
        final journalPath = '$dbPath-journal';
        final walPath = '$dbPath-wal';
        final shmPath = '$dbPath-shm';

        File(dbPath).writeAsStringSync('MALFORMED_HEADER_BYTES');
        File(journalPath).writeAsStringSync('CORRUPT_JOURNAL_BYTES');
        File(walPath).writeAsStringSync('CORRUPT_WAL_BYTES');
        File(shmPath).writeAsStringSync('OBSOLETE_SHM');

        expect(File(journalPath).existsSync(), isTrue);
        expect(File(walPath).existsSync(), isTrue);
        expect(File(shmPath).existsSync(), isTrue);

        final recoveryAppDb = AppDatabase();
        final recoveredDb = await recoveryAppDb.performFailsafeRecovery(
          customPath: dbPath,
          factory: databaseFactoryFfi,
        );

        expect(recoveredDb.isOpen, isTrue);
        expect(File(shmPath).existsSync(), isFalse);

        final files = tempDir.listSync().map((f) => f.path).toList();
        expect(
          files.any((f) => f.contains('journal_test.db-journal.corrupt.')),
          isTrue,
        );
        expect(
          files.any((f) => f.contains('journal_test.db-wal.corrupt.')),
          isTrue,
        );

        final check = await recoveryAppDb.verifyIntegrity(
          full: true,
          targetDb: recoveredDb,
        );
        expect(check.isHealthy, isTrue);

        await recoveryAppDb.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('Concurrent writes during failsafe recovery complete without deadlock or corruption', () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'concurrent_recovery_harness_',
        );
        final dbPath = p.join(tempDir.path, 'concurrent.db');

        final baseDb = AppDatabase();
        var activeDb = await baseDb.initDatabase(
          customPath: dbPath,
          factory: databaseFactoryFfi,
        );

        final operations = <Future<void>>[];
        for (int i = 0; i < 25; i++) {
          final idx = i;
          operations.add(() async {
            try {
              await activeDb.insert(AppDatabase.tableActivityLogs, {
                'package_name_snapshot': 'com.concurrent.log$idx',
                'app_name_snapshot': 'App $idx',
                'event_type': ActivityLog.eventBlockedAttempt,
                'attempted_at': 1000 + idx,
              });
            } catch (_) {}
          }());
        }

        operations.add(() async {
          try {
            activeDb = await baseDb.performFailsafeRecovery(
              customPath: dbPath,
              factory: databaseFactoryFfi,
            );
          } catch (_) {}
        }());

        for (int i = 25; i < 50; i++) {
          final idx = i;
          operations.add(() async {
            try {
              await activeDb.insert(AppDatabase.tableActivityLogs, {
                'package_name_snapshot': 'com.concurrent.log$idx',
                'app_name_snapshot': 'App $idx',
                'event_type': ActivityLog.eventBlockedAttempt,
                'attempted_at': 2000 + idx,
              });
            } catch (_) {}
          }());
        }

        await Future.wait(operations);

        expect(activeDb.isOpen, isTrue);
        final check = await baseDb.verifyIntegrity(
          full: true,
          targetDb: activeDb,
        );
        expect(check.isHealthy, isTrue);

        await baseDb.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
    },
  );

  group(
    'Tier 5 Adversarial Focus 3: Log Synchronization & Extreme Payload Stress',
    () {
      testWidgets(
        'Draining 1,000 pending logs with extreme string sizes and boundary timestamps within Dart range succeeds',
        (tester) async {
          final logRepo = FakeActivityLogRepository();
          final appRepo = FakeBlockedAppRepository([
            BlockedApp(
              id: 7,
              packageName: 'com.popular.app',
              appName: 'Popular App',
              isSelected: true,
              createdAt: DateTime.now(),
            ),
          ]);
          final unlockRepo = FakeTemporaryUnlockRepository();
          final platform = FakeBlockingPlatformChannel(
            accessibilityStatus: 'enabled',
          );

          final massiveString = 'A' * 20000;
          final rawLogs = <Map<String, dynamic>>[];

          for (int i = 0; i < 200; i++) {
            rawLogs.add({
              'packageName': 'com.popular.app',
              'outcome': ActivityLog.outcomeConfirmed,
              'details': 'normal_launch_$i',
              'timestampMs': 1700000000000 + i,
            });
          }

          for (int i = 0; i < 200; i++) {
            rawLogs.add({
              'packageName': 'com.unregistered.app$i',
              'outcome': ActivityLog.outcomeFailed,
              'details': massiveString,
              'timestampMs': 1700000000000 + i,
            });
          }

          for (int i = 0; i < 200; i++) {
            rawLogs.add({
              'packageName': 'com.zero.timestamp',
              'outcome': ActivityLog.outcomeAttempted,
              'details': null,
              'timestampMs': 0,
            });
          }

          for (int i = 0; i < 200; i++) {
            rawLogs.add({
              'packageName': 'com.max.timestamp',
              'outcome': ActivityLog.outcomeNotRequired,
              'details': 'boundary_max',
              'timestampMs': 8640000000000000,
            });
          }

          for (int i = 0; i < 200; i++) {
            rawLogs.add({
              'packageName': '',
              'outcome': 'unknown_custom_outcome',
              'details': 'empty_package',
              'timestampMs': -1000,
            });
          }

          platform.pendingActivityLogs = rawLogs;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: MainScaffold(
                activityLogRepository: logRepo,
                blockedAppRepository: appRepo,
                temporaryUnlockRepository: unlockRepo,
                platformChannel: platform,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(logRepo.logs.length, equals(1000));
          expect(platform.pendingActivityLogs, isEmpty);

          final popularLogs = logRepo.logs
              .where((l) => l.packageNameSnapshot == 'com.popular.app')
              .toList();
          expect(popularLogs.length, equals(200));
          expect(popularLogs.first.appId, equals(7));
          expect(popularLogs.first.appNameSnapshot, equals('Popular App'));

          final largeDetailLogs = logRepo.logs
              .where((l) => l.details == massiveString)
              .toList();
          expect(largeDetailLogs.length, equals(200));

          final maxTimestampLogs = logRepo.logs
              .where((l) => l.packageNameSnapshot == 'com.max.timestamp')
              .toList();
          expect(maxTimestampLogs.length, equals(200));
        },
      );

      test('Gap Empirical Verification: 64-bit Long.MAX_VALUE timestamp crashes DateTime.fromMillisecondsSinceEpoch with RangeError', () {
        const longMax = 9223372036854775807;
        expect(
          () => DateTime.fromMillisecondsSinceEpoch(longMax),
          throwsA(isA<RangeError>()),
        );
      });

      testWidgets(
        'Rapid lifecycle resume cycles drain logs reliably without duplicate loop generation',
        (tester) async {
          final logRepo = FakeActivityLogRepository();
          final appRepo = FakeBlockedAppRepository();
          final unlockRepo = FakeTemporaryUnlockRepository();
          final platform = FakeBlockingPlatformChannel(
            accessibilityStatus: 'enabled',
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: MainScaffold(
                activityLogRepository: logRepo,
                blockedAppRepository: appRepo,
                temporaryUnlockRepository: unlockRepo,
                platformChannel: platform,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          for (int cycle = 0; cycle < 30; cycle++) {
            platform.pendingActivityLogs.add({
              'packageName': 'com.cycle.app$cycle',
              'outcome': ActivityLog.outcomeConfirmed,
              'details': 'cycle_$cycle',
              'timestampMs': 1700000000000 + cycle,
            });

            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump(const Duration(milliseconds: 10));
          }

          expect(logRepo.logs.length, equals(30));
          expect(platform.pendingActivityLogs, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
