import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/models.dart';
import 'package:self_control/data/repositories/repositories.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late BlockedAppRepository blockedAppRepo;
  late TemporaryUnlockRepository unlockRepo;
  late ActivityLogRepository activityLogRepo;
  late SettingsRepository settingsRepo;

  setUp(() async {
    appDatabase = AppDatabase.instance;
    db = await appDatabase.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    blockedAppRepo = BlockedAppRepositoryImpl(db: db);
    unlockRepo = TemporaryUnlockRepositoryImpl(db: db);
    activityLogRepo = ActivityLogRepositoryImpl(db: db);
    settingsRepo = SettingsRepositoryImpl(db: db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('Challenge 1: ON DELETE RESTRICT on temporary_unlocks', () {
    test('strictly forbids deleting blocked_app when active unlock exists', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.target.active',
        'app_name': 'Target App',
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
    });

    test('strictly forbids deleting blocked_app when expired or revoked unlock exists', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.target.history',
        'app_name': 'History App',
        'is_selected': 1,
        'created_at': 1000,
      });

      await db.insert(AppDatabase.tableTemporaryUnlocks, {
        'app_id': appId,
        'start_at': 1000,
        'end_at': 1500,
        'status': TemporaryUnlock.statusExpired,
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
    });

    test('allows deleting blocked_app only after all associated unlocks are removed', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.target.clean',
        'app_name': 'Clean App',
        'is_selected': 1,
        'created_at': 1000,
      });

      final unlockId = await db.insert(AppDatabase.tableTemporaryUnlocks, {
        'app_id': appId,
        'start_at': 1000,
        'end_at': 2000,
        'status': TemporaryUnlock.statusActive,
        'created_at': 1000,
      });

      await db.delete(
        AppDatabase.tableTemporaryUnlocks,
        where: 'id = ?',
        whereArgs: [unlockId],
      );

      final deletedCount = await db.delete(
        AppDatabase.tableBlockedApps,
        where: 'id = ?',
        whereArgs: [appId],
      );
      expect(deletedCount, equals(1));

      final check = await db.query(
        AppDatabase.tableBlockedApps,
        where: 'id = ?',
        whereArgs: [appId],
      );
      expect(check, isEmpty);
    });

    test('unrelated blocked app can be deleted without affecting restricted app', () async {
      final appRestricted = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.app.restricted',
        'app_name': 'Restricted',
        'is_selected': 1,
        'created_at': 1000,
      });

      final appFree = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.app.free',
        'app_name': 'Free',
        'is_selected': 1,
        'created_at': 1000,
      });

      await db.insert(AppDatabase.tableTemporaryUnlocks, {
        'app_id': appRestricted,
        'start_at': 1000,
        'end_at': 2000,
        'status': TemporaryUnlock.statusActive,
        'created_at': 1000,
      });

      final deletedFree = await db.delete(
        AppDatabase.tableBlockedApps,
        where: 'id = ?',
        whereArgs: [appFree],
      );
      expect(deletedFree, equals(1));

      final restrictedStillExists = await db.query(
        AppDatabase.tableBlockedApps,
        where: 'id = ?',
        whereArgs: [appRestricted],
      );
      expect(restrictedStillExists, isNotEmpty);
    });
  });

  group('Challenge 2: ON DELETE SET NULL on activity_logs', () {
    test('preserves activity log history with package_name_snapshot intact on app deletion', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.delete.target',
        'app_name': 'Target For Deletion',
        'is_selected': 1,
        'created_at': 1000,
      });

      final logId1 = await db.insert(AppDatabase.tableActivityLogs, {
        'app_id': appId,
        'package_name_snapshot': 'com.delete.target',
        'app_name_snapshot': 'Target For Deletion',
        'event_type': ActivityLog.eventBlockedAttempt,
        'attempted_at': 2000,
      });

      final logId2 = await db.insert(AppDatabase.tableActivityLogs, {
        'app_id': appId,
        'package_name_snapshot': 'com.delete.target',
        'app_name_snapshot': 'Target For Deletion',
        'event_type': ActivityLog.eventBlockStarted,
        'attempted_at': 3000,
      });

      final rowsDeleted = await db.delete(
        AppDatabase.tableBlockedApps,
        where: 'id = ?',
        whereArgs: [appId],
      );
      expect(rowsDeleted, equals(1));

      final logs = await db.query(
        AppDatabase.tableActivityLogs,
        where: 'id IN (?, ?)',
        whereArgs: [logId1, logId2],
        orderBy: 'id ASC',
      );
      expect(logs.length, equals(2));

      expect(logs[0]['app_id'], isNull);
      expect(logs[0]['package_name_snapshot'], equals('com.delete.target'));
      expect(logs[0]['app_name_snapshot'], equals('Target For Deletion'));
      expect(logs[0]['event_type'], equals(ActivityLog.eventBlockedAttempt));
      expect(logs[0]['attempted_at'], equals(2000));

      expect(logs[1]['app_id'], isNull);
      expect(logs[1]['package_name_snapshot'], equals('com.delete.target'));
      expect(logs[1]['app_name_snapshot'], equals('Target For Deletion'));
      expect(logs[1]['event_type'], equals(ActivityLog.eventBlockStarted));
      expect(logs[1]['attempted_at'], equals(3000));

      final attemptCounts = await activityLogRepo.getAttemptCountsByPackage();
      expect(attemptCounts['com.delete.target'], equals(1));
    });

    test('preserves activity logs when referenced block_session is deleted', () async {
      final sessionId = await db.insert(AppDatabase.tableBlockSessions, {
        'start_at': 1000,
        'end_at': 5000,
        'status': BlockSession.statusActive,
        'created_at': 1000,
      });

      final logId = await db.insert(AppDatabase.tableActivityLogs, {
        'session_id': sessionId,
        'package_name_snapshot': 'com.session.log',
        'app_name_snapshot': 'Session Log',
        'event_type': ActivityLog.eventBlockedAttempt,
        'attempted_at': 2000,
      });

      await db.delete(
        AppDatabase.tableBlockSessions,
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      final logRows = await db.query(
        AppDatabase.tableActivityLogs,
        where: 'id = ?',
        whereArgs: [logId],
      );
      expect(logRows.first['session_id'], isNull);
      expect(logRows.first['package_name_snapshot'], equals('com.session.log'));
    });
  });

  group('Challenge 3: block_rules CHECK constraints and boundary values', () {
    test('rejects duration_minutes <= 0 in duration mode', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'duration',
          'duration_minutes': 0,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'duration',
          'duration_minutes': -1,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'duration',
          'duration_minutes': -99999,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      final validId = await db.insert(AppDatabase.tableBlockRules, {
        'mode': 'duration',
        'duration_minutes': 1,
        'created_at': 1000,
        'updated_at': 1000,
      });
      expect(validId, isPositive);
    });

    test('rejects schedule_start_minute == schedule_end_minute', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 0,
          'schedule_end_minute': 0,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 720,
          'schedule_end_minute': 720,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 1439,
          'schedule_end_minute': 1439,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rejects out-of-range schedule minutes (< 0 or > 1439)', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': -1,
          'schedule_end_minute': 600,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 1440,
          'schedule_end_minute': 600,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 600,
          'schedule_end_minute': -1,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 600,
          'schedule_end_minute': 1440,
          'days_mask': 31,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rejects days_mask boundary violations (mask = 0, mask = 128, mask < 0, mask > 127)', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 500,
          'schedule_end_minute': 600,
          'days_mask': 0,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 500,
          'schedule_end_minute': 600,
          'days_mask': 128,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 500,
          'schedule_end_minute': 600,
          'days_mask': -1,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'schedule',
          'schedule_start_minute': 500,
          'schedule_end_minute': 600,
          'days_mask': 255,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('accepts valid schedule boundaries including overnight and mask 1 / 127', () async {
      final idMinMask = await db.insert(AppDatabase.tableBlockRules, {
        'mode': 'schedule',
        'schedule_start_minute': 0,
        'schedule_end_minute': 1439,
        'days_mask': 1,
        'created_at': 1000,
        'updated_at': 1000,
      });
      expect(idMinMask, isPositive);

      final idMaxMask = await db.insert(AppDatabase.tableBlockRules, {
        'mode': 'schedule',
        'schedule_start_minute': 1439,
        'schedule_end_minute': 0,
        'days_mask': 127,
        'created_at': 1000,
        'updated_at': 1000,
      });
      expect(idMaxMask, isPositive);
    });
  });

  group('Challenge 4: unique constraint on blocked_apps.package_name', () {
    test('rejects duplicate package_name insert with DatabaseException', () async {
      await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.duplicate.app',
        'app_name': 'Original Name',
        'is_selected': 1,
        'created_at': 1000,
      });

      expect(
        () async => await db.insert(AppDatabase.tableBlockedApps, {
          'package_name': 'com.duplicate.app',
          'app_name': 'Clash Name',
          'is_selected': 0,
          'created_at': 2000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      final apps = await db.query(
        AppDatabase.tableBlockedApps,
        where: 'package_name = ?',
        whereArgs: ['com.duplicate.app'],
      );
      expect(apps.length, equals(1));
      expect(apps.first['app_name'], equals('Original Name'));
    });

    test('rejects update that creates duplicate package_name', () async {
      await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.app.first',
        'app_name': 'First',
        'is_selected': 1,
        'created_at': 1000,
      });

      final secondId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.app.second',
        'app_name': 'Second',
        'is_selected': 1,
        'created_at': 1000,
      });

      expect(
        () async => await db.update(
          AppDatabase.tableBlockedApps,
          {'package_name': 'com.app.first'},
          where: 'id = ?',
          whereArgs: [secondId],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('Challenge 5: Repository Concurrency and Stress Harness', () {
    test('handles 100 concurrent asynchronous log writes without deadlock or loss', () async {
      final futures = List<Future<void>>.generate(100, (i) {
        return activityLogRepo.logEvent(
          ActivityLog(
            packageNameSnapshot: 'com.concurrent.app${i % 5}',
            appNameSnapshot: 'Concurrent App ${i % 5}',
            eventType: ActivityLog.eventBlockedAttempt,
            attemptedAt: DateTime.fromMillisecondsSinceEpoch(1000 + i),
          ),
        );
      });

      await Future.wait(futures);

      final logs = await activityLogRepo.getLogs(limit: 200);
      expect(logs.length, equals(100));

      final attemptCounts = await activityLogRepo.getAttemptCountsByPackage();
      int totalCount = 0;
      for (final count in attemptCounts.values) {
        totalCount += count;
      }
      expect(totalCount, equals(100));
    });

    test('handles concurrent saveApps and setAppSelected operations', () async {
      final appsBatch1 = List.generate(
        20,
        (i) => BlockedApp(
          packageName: 'com.batch.app$i',
          appName: 'Initial $i',
          isSelected: false,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      await blockedAppRepo.saveApps(appsBatch1);

      final futures = <Future<void>>[];
      for (int i = 0; i < 20; i++) {
        final idx = i;
        futures.add(
          blockedAppRepo.saveApps([
            BlockedApp(
              packageName: 'com.batch.app$idx',
              appName: 'Updated $idx',
              isSelected: true,
              createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
            ),
          ]),
        );
        futures.add(
          blockedAppRepo.setAppSelected('com.batch.app$idx', idx % 2 == 0),
        );
      }

      await Future.wait(futures);

      final allApps = await blockedAppRepo.getAllApps();
      expect(allApps.length, equals(20));

      for (int i = 0; i < 20; i++) {
        final app = allApps.firstWhere((a) => a.packageName == 'com.batch.app$i');
        expect(app.appName, equals('Updated $i'));
      }
    });

    test('handles concurrent password setting and verification', () async {
      final futures = List.generate(10, (i) {
        return settingsRepo.setPassword('password_$i');
      });
      await Future.wait(futures);

      final hash = await settingsRepo.getSetting(AppSetting.keyPasswordHash);
      final salt = await settingsRepo.getSetting(AppSetting.keyPasswordSalt);

      expect(hash, isNotNull);
      expect(hash, isNotEmpty);
      expect(salt, isNotNull);
      expect(salt, isNotEmpty);

      bool verifiedAny = false;
      for (int i = 0; i < 10; i++) {
        if (await settingsRepo.verifyPassword('password_$i')) {
          verifiedAny = true;
          break;
        }
      }
      expect(verifiedAny, isTrue);
    });

    test('handles concurrent temporary unlocks and batch expiration', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.stress.unlock',
        'app_name': 'Stress Unlock',
        'is_selected': 1,
        'created_at': 1000,
      });

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final createFutures = List.generate(30, (i) {
        return unlockRepo.createUnlock(
          TemporaryUnlock(
            appId: appId,
            startAt: DateTime.fromMillisecondsSinceEpoch(now - 5000),
            endAt: DateTime.fromMillisecondsSinceEpoch(i < 15 ? now - 1000 : now + 50000),
            status: TemporaryUnlock.statusActive,
            createdAt: DateTime.fromMillisecondsSinceEpoch(now - 5000),
          ),
        );
      });

      await Future.wait(createFutures);

      await unlockRepo.expireOutdatedUnlocks();

      final expiredRows = await db.query(
        AppDatabase.tableTemporaryUnlocks,
        where: 'app_id = ? AND status = ?',
        whereArgs: [appId, TemporaryUnlock.statusExpired],
      );
      expect(expiredRows.length, equals(15));

      final activeRows = await db.query(
        AppDatabase.tableTemporaryUnlocks,
        where: 'app_id = ? AND status = ?',
        whereArgs: [appId, TemporaryUnlock.statusActive],
      );
      expect(activeRows.length, equals(15));
    });
  });
}
