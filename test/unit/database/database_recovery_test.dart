import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Integrity and Failsafe Recovery Tests', () {
    test('verifyIntegrity quick check returns healthy on clean database', () async {
      final appDb = AppDatabase.instance;
      final db = await appDb.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );

      final quickResult = await appDb.verifyIntegrity(full: false, targetDb: db);
      expect(quickResult.isHealthy, isTrue);
      expect(quickResult.isIntegrityOk, isTrue);
      expect(quickResult.isForeignKeyOk, isTrue);

      final fullResult = await appDb.verifyIntegrity(full: true, targetDb: db);
      expect(fullResult.isHealthy, isTrue);
      expect(fullResult.isIntegrityOk, isTrue);
      expect(fullResult.isForeignKeyOk, isTrue);
      expect(fullResult.integrityErrors, isEmpty);
      expect(fullResult.foreignKeyViolations, isEmpty);

      await appDb.close();
    });

    test('verifyIntegrity full check detects foreign key violations', () async {
      final appDb = AppDatabase.instance;
      final db = await appDb.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );

      await db.execute('PRAGMA foreign_keys = OFF;');
      await db.rawInsert('''
        INSERT INTO ${AppDatabase.tableTemporaryUnlocks}
          (id, app_id, session_id, start_at, end_at, status, created_at)
        VALUES (999, 88888, NULL, 1000, 2000, 'active', 1000);
      ''');
      await db.execute('PRAGMA foreign_keys = ON;');

      final result = await appDb.verifyIntegrity(full: true, targetDb: db);
      expect(result.isHealthy, isFalse);
      expect(result.isForeignKeyOk, isFalse);
      expect(result.foreignKeyViolations, isNotEmpty);

      await appDb.close();
    });

    test('resetToDefaults clears data and re-seeds default settings', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_reset_test_');
      final dbPath = p.join(tempDir.path, 'reset_test.db');
      final appDb = AppDatabase.instance;

      final db = await appDb.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.test.app',
        'app_name': 'Test App',
        'is_selected': 1,
        'created_at': 1000,
      });

      final appsBefore = await db.query(AppDatabase.tableBlockedApps);
      expect(appsBefore.length, 1);

      final resetDb = await appDb.resetToDefaults(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      final appsAfter = await resetDb.query(AppDatabase.tableBlockedApps);
      expect(appsAfter, isEmpty);

      final settings = await resetDb.query(AppDatabase.tableAppSettings);
      expect(settings, isNotEmpty);

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('failsafe recovery backs up corrupt database and creates pristine database', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_corrupt_test_');
      final dbPath = p.join(tempDir.path, 'corrupt_test.db');
      final corruptFile = File(dbPath);
      corruptFile.writeAsStringSync('THIS_IS_CORRUPT_NON_SQLITE_GARBAGE_DATA');

      final appDb = AppDatabase.instance;
      final recoveredDb = await appDb.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
        enableAutoRecovery: true,
      );

      expect(recoveredDb.isOpen, isTrue);

      final tables = await recoveredDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      );
      final tableNames = tables.map((r) => r['name'] as String).toSet();
      expect(tableNames, contains(AppDatabase.tableBlockedApps));
      expect(tableNames, contains(AppDatabase.tableActivityLogs));

      final backupFiles = tempDir.listSync().where((f) => f.path.contains('.corrupt.')).toList();
      expect(backupFiles, isNotEmpty);

      final logs = await recoveredDb.query(AppDatabase.tableActivityLogs);
      expect(logs.any((l) => l['event_type'] == 'failsafe_recovery'), isTrue);

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('schema migration v1 to v2 adds outcome and details columns', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_migration_test_');
      final dbPath = p.join(tempDir.path, 'migration_test.db');

      final v1Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE ${AppDatabase.tableActivityLogs} (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_id INTEGER,
                session_id INTEGER,
                package_name_snapshot TEXT NOT NULL,
                app_name_snapshot TEXT NOT NULL,
                event_type TEXT NOT NULL,
                attempted_at INTEGER NOT NULL
              );
            ''');
            await db.insert(AppDatabase.tableActivityLogs, {
              'package_name_snapshot': 'com.v1.app',
              'app_name_snapshot': 'V1 App',
              'event_type': 'blocked_attempt',
              'attempted_at': 1000,
            });
          },
        ),
      );
      await v1Db.close();

      final appDb = AppDatabase.instance;
      final v2Db = await appDb.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
        enableAutoRecovery: false,
      );

      final rows = await v2Db.query(AppDatabase.tableActivityLogs);
      expect(rows.length, 1);
      expect(rows.first['package_name_snapshot'], 'com.v1.app');
      expect(rows.first['outcome'], 'confirmed');
      expect(rows.first['details'], isNull);

      await v2Db.insert(AppDatabase.tableActivityLogs, {
        'package_name_snapshot': 'com.v2.app',
        'app_name_snapshot': 'V2 App',
        'event_type': 'blocked_attempt',
        'outcome': 'failed',
        'details': 'SecurityException: Permission Denial',
        'attempted_at': 2000,
      });

      final updatedRows = await v2Db.query(AppDatabase.tableActivityLogs);
      expect(updatedRows.length, 2);
      expect(updatedRows.last['outcome'], 'failed');
      expect(updatedRows.last['details'], 'SecurityException: Permission Denial');

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
