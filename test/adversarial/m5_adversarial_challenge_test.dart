import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  group('Milestone 5 Adversarial Focus 1: Database Integrity Verification', () {
    test('PRAGMA quick_check and full integrity_check return healthy on clean DB', () async {
      final appDb = AppDatabase();
      final db = await appDb.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );

      final quickResult = await appDb.verifyIntegrity(full: false, targetDb: db);
      expect(quickResult.isHealthy, isTrue);
      expect(quickResult.isIntegrityOk, isTrue);
      expect(quickResult.isForeignKeyOk, isTrue);
      expect(quickResult.integrityErrors, isEmpty);

      final fullResult = await appDb.verifyIntegrity(full: true, targetDb: db);
      expect(fullResult.isHealthy, isTrue);
      expect(fullResult.isIntegrityOk, isTrue);
      expect(fullResult.isForeignKeyOk, isTrue);
      expect(fullResult.integrityErrors, isEmpty);
      expect(fullResult.foreignKeyViolations, isEmpty);

      await appDb.close();
    });

    test('PRAGMA foreign_key_check detects relational violations whereas quick_check does not', () async {
      final appDb = AppDatabase();
      final db = await appDb.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );

      await db.execute('PRAGMA foreign_keys = OFF;');
      await db.rawInsert('''
        INSERT INTO ${AppDatabase.tableTemporaryUnlocks}
          (id, app_id, session_id, start_at, end_at, status, created_at)
        VALUES (101, 77777, NULL, 1000, 2000, 'active', 1000);
      ''');
      await db.rawInsert('''
        INSERT INTO ${AppDatabase.tableActivityLogs}
          (id, app_id, session_id, package_name_snapshot, app_name_snapshot, event_type, outcome, attempted_at)
        VALUES (202, 88888, NULL, 'com.ghost.app', 'Ghost App', 'blocked_attempt', 'confirmed', 1000);
      ''');
      await db.execute('PRAGMA foreign_keys = ON;');

      final quickResult = await appDb.verifyIntegrity(full: false, targetDb: db);
      expect(quickResult.isHealthy, isTrue);
      expect(quickResult.isIntegrityOk, isTrue);

      final fullResult = await appDb.verifyIntegrity(full: true, targetDb: db);
      expect(fullResult.isHealthy, isFalse);
      expect(fullResult.isForeignKeyOk, isFalse);
      expect(fullResult.foreignKeyViolations.length, 2);
      expect(fullResult.foreignKeyViolations.any((v) => v.contains(AppDatabase.tableTemporaryUnlocks)), isTrue);
      expect(fullResult.foreignKeyViolations.any((v) => v.contains(AppDatabase.tableActivityLogs)), isTrue);

      await appDb.close();
    });

    test('PRAGMA quick_check and openDatabase detect corrupted headers and corrupted page blocks', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_integrity_corrupt_test_');
      final dbPath = p.join(tempDir.path, 'corrupted_blocks.db');

      final appDb = AppDatabase();
      final db = await appDb.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );
      for (var i = 0; i < 50; i++) {
        await db.insert(AppDatabase.tableBlockedApps, {
          'package_name': 'com.test.app$i',
          'app_name': 'Test App $i',
          'is_selected': 1,
          'created_at': 1000 + i,
        });
      }
      await appDb.close();

      final file = File(dbPath);
      final bytes = file.readAsBytesSync();
      for (var i = 16; i < 48 && i < bytes.length; i++) {
        bytes[i] = 0xFF;
      }
      file.writeAsBytesSync(bytes);

      var caughtException = false;
      try {
        final corruptDb = await databaseFactoryFfi.openDatabase(dbPath);
        final check = await corruptDb.rawQuery('PRAGMA quick_check;');
        final status = check.first.values.first.toString().toLowerCase();
        if (status != 'ok') {
          caughtException = true;
        }
        await corruptDb.close();
      } catch (_) {
        caughtException = true;
      }
      expect(caughtException, isTrue);

      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Milestone 5 Adversarial Focus 2: Corrupt File Recovery Routine', () {
    test('performFailsafeRecovery archives corrupt file, deletes -shm, and restores fresh DB', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_failsafe_test_');
      final dbPath = p.join(tempDir.path, 'active.db');
      final walPath = '$dbPath-wal';
      final shmPath = '$dbPath-shm';

      File(dbPath).writeAsStringSync('NOT_A_SQLITE_DATABASE_CORRUPT_BYTES_XYZ_12345');
      File(walPath).writeAsStringSync('WAL_CORRUPT_BYTES');
      File(shmPath).writeAsStringSync('SHM_TEMPORARY_INDEX');

      expect(File(dbPath).existsSync(), isTrue);
      expect(File(walPath).existsSync(), isTrue);
      expect(File(shmPath).existsSync(), isTrue);

      final appDb = AppDatabase();
      final recoveredDb = await appDb.performFailsafeRecovery(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      expect(recoveredDb.isOpen, isTrue);
      expect(File(shmPath).existsSync(), isFalse);

      final backups = tempDir.listSync().where((f) => f.path.contains('.corrupt.')).toList();
      expect(backups.length, greaterThanOrEqualTo(2));
      expect(backups.any((f) => f.path.contains('active.db.corrupt.')), isTrue);
      expect(backups.any((f) => f.path.contains('active.db-wal.corrupt.')), isTrue);

      final tables = await recoveredDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      );
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll([
        AppDatabase.tableBlockedApps,
        AppDatabase.tableBlockRules,
        AppDatabase.tableBlockSessions,
        AppDatabase.tableTemporaryUnlocks,
        AppDatabase.tableActivityLogs,
        AppDatabase.tableAppSettings,
      ]));

      final settings = await recoveredDb.query(AppDatabase.tableAppSettings);
      final settingsMap = {for (final row in settings) row['key'] as String: row['value'] as String};
      expect(settingsMap['waiting_duration_seconds'], '300');
      expect(settingsMap['custom_lock_message'], 'Tetap fokus pada tujuanmu.');
      expect(settingsMap['default_unlock_duration_seconds'], '600');

      final logs = await recoveredDb.query(AppDatabase.tableActivityLogs);
      expect(logs.length, 1);
      expect(logs.first['event_type'], 'failsafe_recovery');
      expect(logs.first['outcome'], 'confirmed');
      expect(logs.first['details'], 'database_recreated_after_corruption');

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('initDatabase automatic recovery handles corruption seamlessly without bubbling exception to main()', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_main_startup_test_');
      final dbPath = p.join(tempDir.path, 'startup_corrupt.db');
      File(dbPath).writeAsStringSync('RANDOM_JUNK_MALFORMED_HEADER');

      final appDb = AppDatabase();
      Database? openedDb;
      Object? unhandledError;

      try {
        openedDb = await appDb.initDatabase(
          customPath: dbPath,
          factory: databaseFactoryFfi,
          enableAutoRecovery: true,
        );
      } catch (e) {
        unhandledError = e;
      }

      expect(unhandledError, isNull);
      expect(openedDb, isNotNull);
      expect(openedDb!.isOpen, isTrue);

      final integrity = await appDb.verifyIntegrity(full: true, targetDb: openedDb);
      expect(integrity.isHealthy, isTrue);

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Milestone 5 Adversarial Focus 3: Database Migration v1 -> v2', () {
    test('v1 to v2 migration sets outcome default to confirmed, allows details, and supports all 4 outcome statuses', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_migration_full_');
      final dbPath = p.join(tempDir.path, 'v1_migration.db');

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
            await db.execute('''
              CREATE TABLE ${AppDatabase.tableAppSettings} (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
              );
            ''');
            await db.insert(AppDatabase.tableActivityLogs, {
              'package_name_snapshot': 'com.v1.old',
              'app_name_snapshot': 'Old App',
              'event_type': 'blocked_attempt',
              'attempted_at': 1500,
            });
          },
        ),
      );
      await v1Db.close();

      final appDb = AppDatabase();
      final v2Db = await appDb.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
        enableAutoRecovery: false,
      );

      final oldRows = await v2Db.query(AppDatabase.tableActivityLogs, where: 'package_name_snapshot = ?', whereArgs: ['com.v1.old']);
      expect(oldRows.length, 1);
      expect(oldRows.first['outcome'], 'confirmed');
      expect(oldRows.first['details'], isNull);

      final outcomesToTest = [
        ActivityLog.outcomeAttempted,
        ActivityLog.outcomeConfirmed,
        ActivityLog.outcomeFailed,
        ActivityLog.outcomeNotRequired,
      ];

      for (var i = 0; i < outcomesToTest.length; i++) {
        final outcome = outcomesToTest[i];
        final id = await v2Db.insert(AppDatabase.tableActivityLogs, {
          'package_name_snapshot': 'com.package.$outcome',
          'app_name_snapshot': 'App $outcome',
          'event_type': ActivityLog.eventBlockedAttempt,
          'outcome': outcome,
          'details': 'Details for $outcome at index $i',
          'attempted_at': 2000 + i,
        });
        expect(id, greaterThan(0));
      }

      final allLogs = await v2Db.query(AppDatabase.tableActivityLogs, orderBy: 'attempted_at ASC');
      expect(allLogs.length, 5);

      final insertedOutcomes = allLogs.skip(1).map((r) => r['outcome'] as String).toList();
      expect(insertedOutcomes, equals(outcomesToTest));

      final insertedDetails = allLogs.skip(1).map((r) => r['details'] as String).toList();
      expect(insertedDetails.every((d) => d.startsWith('Details for ')), isTrue);

      final indexCheck = await v2Db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_logs_outcome';",
      );
      expect(indexCheck.isNotEmpty, isTrue);

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Milestone 5 Adversarial Focus 4: Emergency Recovery in Settings', () {
    test('resetToDefaults clears data, resets settings to defaults, and restores pristine state', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_emergency_reset_');
      final dbPath = p.join(tempDir.path, 'emergency.db');

      final appDb = AppDatabase();
      final db = await appDb.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.custom.app',
        'app_name': 'Custom App',
        'is_selected': 1,
        'created_at': 1000,
      });
      await db.update(
        AppDatabase.tableAppSettings,
        {'value': '900', 'updated_at': 2000},
        where: 'key = ?',
        whereArgs: ['waiting_duration_seconds'],
      );
      await db.update(
        AppDatabase.tableAppSettings,
        {'value': 'Hati-hati dan tetap fokus!', 'updated_at': 2000},
        where: 'key = ?',
        whereArgs: ['custom_lock_message'],
      );
      await db.update(
        AppDatabase.tableAppSettings,
        {'value': 'salted_hash_val', 'updated_at': 2000},
        where: 'key = ?',
        whereArgs: ['password_hash'],
      );

      final resetDb = await appDb.resetToDefaults(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      final appsAfter = await resetDb.query(AppDatabase.tableBlockedApps);
      expect(appsAfter, isEmpty);

      final settingsAfter = await resetDb.query(AppDatabase.tableAppSettings);
      final map = {for (final r in settingsAfter) r['key'] as String: r['value'] as String};
      expect(map['waiting_duration_seconds'], '300');
      expect(map['custom_lock_message'], 'Tetap fokus pada tujuanmu.');
      expect(map['password_hash'], '');
      expect(map['password_salt'], '');
      expect(map['default_unlock_duration_seconds'], '600');

      await resetDb.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.new.app',
        'app_name': 'New App',
        'is_selected': 1,
        'created_at': 3000,
      });
      final appsReinserted = await resetDb.query(AppDatabase.tableBlockedApps);
      expect(appsReinserted.length, 1);

      await appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('SettingsScreen UI emergency reset dialog interaction and snackbar verification', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'waiting_duration_seconds': '900',
          'custom_lock_message': 'Pesan Kustom Sebelum Reset',
          'default_unlock_duration_seconds': '900',
        },
      );
      final fakeDb = FakeAppDatabase();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsRepository: settingsRepo,
            appDatabase: fakeDb,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reset Darurat'), findsOneWidget);

      await tester.tap(find.text('Reset Darurat'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi Reset'), findsOneWidget);
      expect(
        find.text('Tindakan ini akan mengembalikan seluruh pengaturan ke bawaan dan menghapus riwayat blokir. Lanjutkan?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi Reset'), findsNothing);
      expect(fakeDb.resetToDefaultsCalled, isFalse);

      await tester.tap(find.text('Reset Darurat'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(fakeDb.resetToDefaultsCalled, isTrue);
      expect(find.text('Seluruh pengaturan dan data berhasil direset.'), findsOneWidget);
    });
  });
}
