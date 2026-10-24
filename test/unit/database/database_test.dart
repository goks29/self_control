import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    appDatabase = AppDatabase.instance;
    db = await appDatabase.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('Database Schema and Configuration Tests', () {
    test('enforces PRAGMA foreign_keys = ON', () async {
      final result = await db.rawQuery('PRAGMA foreign_keys;');
      expect(result.first.values.first, equals(1));
    });

    test('creates all 6 tables and 4 indexes', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      );
      final tableNames = tables.map((r) => r['name'] as String).toSet();
      expect(
        tableNames,
        containsAll([
          'blocked_apps',
          'block_rules',
          'block_sessions',
          'temporary_unlocks',
          'activity_logs',
          'app_settings',
        ]),
      );

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%';",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toSet();
      expect(
        indexNames,
        containsAll([
          'idx_logs_attempted_at',
          'idx_logs_package_time',
          'idx_sessions_status',
          'idx_unlocks_app_status',
        ]),
      );
    });

    test('seeds default settings on database creation', () async {
      final settings = await db.query(AppDatabase.tableAppSettings);
      final map = {
        for (final row in settings) row['key'] as String: row['value'] as String,
      };

      expect(map['waiting_duration_seconds'], equals('300'));
      expect(map['custom_lock_message'], equals('Tetap fokus pada tujuanmu.'));
      expect(map['default_unlock_duration_seconds'], equals('600'));
      expect(map.containsKey('password_hash'), isTrue);
      expect(map.containsKey('password_salt'), isTrue);
    });
  });

  group('Referential Integrity and Cascade Tests', () {
    test('enforces ON DELETE RESTRICT on temporary_unlocks referencing blocked_apps', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.restricted.app',
        'app_name': 'Restricted App',
        'is_selected': 1,
        'created_at': 1000,
      });

      await db.insert(AppDatabase.tableTemporaryUnlocks, {
        'app_id': appId,
        'start_at': 1000,
        'end_at': 2000,
        'status': 'active',
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

    test('enforces ON DELETE SET NULL on activity_logs referencing blocked_apps', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.logged.app',
        'app_name': 'Logged App',
        'is_selected': 1,
        'created_at': 1000,
      });

      final logId = await db.insert(AppDatabase.tableActivityLogs, {
        'app_id': appId,
        'package_name_snapshot': 'com.logged.app',
        'app_name_snapshot': 'Logged App',
        'event_type': 'blocked_attempt',
        'attempted_at': 1000,
      });

      await db.delete(
        AppDatabase.tableBlockedApps,
        where: 'id = ?',
        whereArgs: [appId],
      );

      final logRows = await db.query(
        AppDatabase.tableActivityLogs,
        where: 'id = ?',
        whereArgs: [logId],
      );
      expect(logRows.first['app_id'], isNull);
      expect(logRows.first['package_name_snapshot'], equals('com.logged.app'));
    });

    test('enforces ON DELETE SET NULL on temporary_unlocks referencing block_sessions', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.unlock.app',
        'app_name': 'Unlock App',
        'is_selected': 1,
        'created_at': 1000,
      });

      final sessionId = await db.insert(AppDatabase.tableBlockSessions, {
        'start_at': 1000,
        'end_at': 5000,
        'status': 'active',
        'created_at': 1000,
      });

      final unlockId = await db.insert(AppDatabase.tableTemporaryUnlocks, {
        'app_id': appId,
        'session_id': sessionId,
        'start_at': 1000,
        'end_at': 2000,
        'status': 'active',
        'created_at': 1000,
      });

      await db.delete(
        AppDatabase.tableBlockSessions,
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      final unlockRows = await db.query(
        AppDatabase.tableTemporaryUnlocks,
        where: 'id = ?',
        whereArgs: [unlockId],
      );
      expect(unlockRows.first['session_id'], isNull);
      expect(unlockRows.first['app_id'], equals(appId));
    });
  });

  group('Check Constraints Tests', () {
    test('enforces unique package_name in blocked_apps', () async {
      await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.unique.app',
        'app_name': 'App 1',
        'is_selected': 1,
        'created_at': 1000,
      });

      expect(
        () async => await db.insert(AppDatabase.tableBlockedApps, {
          'package_name': 'com.unique.app',
          'app_name': 'App 2',
          'is_selected': 1,
          'created_at': 2000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('enforces is_selected binary constraint in blocked_apps', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockedApps, {
          'package_name': 'com.binary.app',
          'app_name': 'Binary App',
          'is_selected': 2,
          'created_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('enforces block_rules mode and field constraints', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockRules, {
          'mode': 'invalid_mode',
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

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
          'mode': 'schedule',
          'schedule_start_minute': 500,
          'schedule_end_minute': 500,
          'days_mask': 31,
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

      final validRuleId = await db.insert(AppDatabase.tableBlockRules, {
        'mode': 'schedule',
        'schedule_start_minute': 1320,
        'schedule_end_minute': 420,
        'days_mask': 31,
        'is_enabled': 1,
        'created_at': 1000,
        'updated_at': 1000,
      });
      expect(validRuleId, isPositive);
    });

    test('enforces end_at > start_at on block_sessions and temporary_unlocks', () async {
      expect(
        () async => await db.insert(AppDatabase.tableBlockSessions, {
          'start_at': 2000,
          'end_at': 1000,
          'status': 'active',
          'created_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.check.app',
        'app_name': 'Check App',
        'is_selected': 1,
        'created_at': 1000,
      });

      expect(
        () async => await db.insert(AppDatabase.tableTemporaryUnlocks, {
          'app_id': appId,
          'start_at': 2000,
          'end_at': 2000,
          'status': 'active',
          'created_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
