import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/block_session.dart';
import 'package:self_control/data/repositories/block_session_repository.dart';
import 'package:self_control/data/repositories/block_session_repository_impl.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late BlockSessionRepository repository;

  setUp(() async {
    appDatabase = AppDatabase.instance;
    db = await appDatabase.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = BlockSessionRepositoryImpl(db: db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('BlockSession Model Isolation Tests', () {
    test('supports packageName serialization, copyWith, and equality', () {
      final start = DateTime(2026, 10, 24, 10, 0);
      final end = DateTime(2026, 10, 24, 11, 0);
      final session = BlockSession(
        id: 1,
        packageName: 'com.social.app',
        startAt: start,
        endAt: end,
        status: BlockSession.statusActive,
        createdAt: start,
      );

      final map = session.toMap();
      expect(map['package_name'], equals('com.social.app'));

      final fromMap = BlockSession.fromMap(map);
      expect(fromMap, equals(session));
      expect(fromMap.packageName, equals('com.social.app'));
      expect(fromMap.hashCode, equals(session.hashCode));
      expect(fromMap.toString(), contains('com.social.app'));

      final copy = session.copyWith(packageName: 'com.another.app');
      expect(copy.packageName, equals('com.another.app'));
      expect(copy, isNot(equals(session)));

      final legacyMap = <String, dynamic>{
        'id': 2,
        'start_at': start.millisecondsSinceEpoch,
        'end_at': end.millisecondsSinceEpoch,
        'status': BlockSession.statusActive,
        'created_at': start.millisecondsSinceEpoch,
      };
      final fromLegacy = BlockSession.fromMap(legacyMap);
      expect(fromLegacy.packageName, isNull);
    });
  });

  group('Database Migration v2 to v3 Tests', () {
    test('migrates schema cleanly from v2 to v3 with package_name column and index', () async {
      final dbPath = p.join(await getDatabasesPath(), 'test_migration_v2_v3.db');
      await databaseFactoryFfi.deleteDatabase(dbPath);

      final migrationDb = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE block_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_at INTEGER NOT NULL,
                end_at INTEGER NOT NULL,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL
              );
            ''');
            await db.execute('CREATE INDEX idx_sessions_status ON block_sessions(status);');
            await db.insert('block_sessions', {
              'start_at': 1000,
              'end_at': 2000,
              'status': 'active',
              'created_at': 1000,
            });
          },
        ),
      );

      await migrationDb.close();

      final upgradedDb = await appDatabase.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      final row = await upgradedDb.query(AppDatabase.tableBlockSessions);
      expect(row.length, equals(1));
      expect(row.first.containsKey('package_name'), isTrue);
      expect(row.first['package_name'], isNull);

      await upgradedDb.insert(AppDatabase.tableBlockSessions, {
        'package_name': 'com.migrated.app',
        'start_at': 3000,
        'end_at': 4000,
        'status': 'active',
        'created_at': 3000,
      });

      final newRow = await upgradedDb.query(
        AppDatabase.tableBlockSessions,
        where: 'package_name = ?',
        whereArgs: ['com.migrated.app'],
      );
      expect(newRow.length, equals(1));
      expect(newRow.first['package_name'], equals('com.migrated.app'));

      await databaseFactoryFfi.deleteDatabase(dbPath);
    });
  });

  group('BlockSessionRepository Isolation Tests', () {
    test('creates and retrieves active sessions isolated per package name', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(1000000);
      final sessionA = BlockSession(
        packageName: 'com.app.a',
        startAt: t0,
        endAt: t0.add(const Duration(seconds: 300)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );
      final sessionB = BlockSession(
        packageName: 'com.app.b',
        startAt: t0.add(const Duration(seconds: 60)),
        endAt: t0.add(const Duration(seconds: 660)),
        status: BlockSession.statusActive,
        createdAt: t0.add(const Duration(seconds: 60)),
      );

      final idA = await repository.createSession(sessionA);
      final idB = await repository.createSession(sessionB);

      expect(idA, isPositive);
      expect(idB, isPositive);

      final activeA = await repository.getActiveSessionForPackage('com.app.a');
      final activeB = await repository.getActiveSessionForPackage('com.app.b');

      expect(activeA, isNotNull);
      expect(activeA!.id, equals(idA));
      expect(activeA.packageName, equals('com.app.a'));
      expect(activeA.startAt, equals(sessionA.startAt));
      expect(activeA.endAt, equals(sessionA.endAt));

      expect(activeB, isNotNull);
      expect(activeB!.id, equals(idB));
      expect(activeB.packageName, equals('com.app.b'));
      expect(activeB.startAt, equals(sessionB.startAt));
      expect(activeB.endAt, equals(sessionB.endAt));

      expect(activeA.endAt, isNot(equals(activeB.endAt)));
    });

    test('completeActiveSessionsForPackage only marks target package completed', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(2000000);
      final sessionA = BlockSession(
        packageName: 'com.app.a',
        startAt: t0,
        endAt: t0.add(const Duration(seconds: 300)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );
      final sessionB = BlockSession(
        packageName: 'com.app.b',
        startAt: t0,
        endAt: t0.add(const Duration(seconds: 500)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );
      final sessionC = BlockSession(
        packageName: 'com.app.c',
        startAt: t0,
        endAt: t0.add(const Duration(seconds: 600)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );

      await repository.createSession(sessionA);
      final idB = await repository.createSession(sessionB);
      final idC = await repository.createSession(sessionC);

      await repository.completeActiveSessionsForPackage('com.app.a');

      final activeA = await repository.getActiveSessionForPackage('com.app.a');
      final activeB = await repository.getActiveSessionForPackage('com.app.b');
      final activeC = await repository.getActiveSessionForPackage('com.app.c');

      expect(activeA, isNull);

      expect(activeB, isNotNull);
      expect(activeB!.id, equals(idB));
      expect(activeB.packageName, equals('com.app.b'));
      expect(activeB.status, equals(BlockSession.statusActive));

      expect(activeC, isNotNull);
      expect(activeC!.id, equals(idC));
      expect(activeC.packageName, equals('com.app.c'));
      expect(activeC.status, equals(BlockSession.statusActive));

      final rawA = await db.query(
        AppDatabase.tableBlockSessions,
        where: 'package_name = ?',
        whereArgs: ['com.app.a'],
      );
      expect(rawA.first['status'], equals(BlockSession.statusCompleted));

      await repository.completeActiveSessionsForPackage('com.app.b');
      expect(await repository.getActiveSessionForPackage('com.app.b'), isNull);
      expect(await repository.getActiveSessionForPackage('com.app.c'), isNotNull);
    });

    test('returns null for non-existent package or package without active session', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(3000000);
      expect(await repository.getActiveSessionForPackage('com.unknown.app'), isNull);

      await repository.createSession(
        BlockSession(
          packageName: 'com.completed.app',
          startAt: t0,
          endAt: t0.add(const Duration(seconds: 300)),
          status: BlockSession.statusCompleted,
          createdAt: t0,
        ),
      );
      await repository.createSession(
        BlockSession(
          packageName: 'com.cancelled.app',
          startAt: t0,
          endAt: t0.add(const Duration(seconds: 300)),
          status: BlockSession.statusCancelled,
          createdAt: t0,
        ),
      );

      expect(await repository.getActiveSessionForPackage('com.completed.app'), isNull);
      expect(await repository.getActiveSessionForPackage('com.cancelled.app'), isNull);

      await repository.completeActiveSessionsForPackage('com.unknown.app');
    });

    test('returns newest active session when multiple active sessions exist for same package', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(4000000);
      final olderSession = BlockSession(
        packageName: 'com.app.duplicate',
        startAt: t0,
        endAt: t0.add(const Duration(seconds: 300)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );
      final newerSession = BlockSession(
        packageName: 'com.app.duplicate',
        startAt: t0.add(const Duration(seconds: 50)),
        endAt: t0.add(const Duration(seconds: 350)),
        status: BlockSession.statusActive,
        createdAt: t0.add(const Duration(seconds: 50)),
      );

      await repository.createSession(olderSession);
      final newerId = await repository.createSession(newerSession);

      final active = await repository.getActiveSessionForPackage('com.app.duplicate');
      expect(active, isNotNull);
      expect(active!.id, equals(newerId));
      expect(active.startAt, equals(newerSession.startAt));

      await repository.completeActiveSessionsForPackage('com.app.duplicate');
      expect(await repository.getActiveSessionForPackage('com.app.duplicate'), isNull);

      final allForPackage = await db.query(
        AppDatabase.tableBlockSessions,
        where: 'package_name = ?',
        whereArgs: ['com.app.duplicate'],
      );
      for (final row in allForPackage) {
        expect(row['status'], equals(BlockSession.statusCompleted));
      }
    });

    test('preserves global sessions with null package name without interference', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(5000000);
      final globalSession = BlockSession(
        startAt: t0,
        endAt: t0.add(const Duration(hours: 1)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );
      final packageSession = BlockSession(
        packageName: 'com.app.specific',
        startAt: t0,
        endAt: t0.add(const Duration(minutes: 5)),
        status: BlockSession.statusActive,
        createdAt: t0,
      );

      final globalId = await repository.createSession(globalSession);
      final packageId = await repository.createSession(packageSession);

      final activeGlobal = await repository.getActiveSession();
      expect(activeGlobal, isNotNull);

      final activePackage = await repository.getActiveSessionForPackage('com.app.specific');
      expect(activePackage, isNotNull);
      expect(activePackage!.id, equals(packageId));

      expect(await repository.getActiveSessionForPackage('com.other.app'), isNull);

      await repository.completeActiveSessionsForPackage('com.app.specific');
      expect(await repository.getActiveSessionForPackage('com.app.specific'), isNull);

      final recheckedGlobal = await repository.getActiveSession();
      expect(recheckedGlobal, isNotNull);
      expect(recheckedGlobal!.id, equals(globalId));
    });
  });
}
