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

  group('M2 Challenger - Schema v3 & Index Verification', () {
    test('confirms idx_sessions_package_status index definition and columns', () async {
      final indexList = await db.rawQuery("PRAGMA index_list('block_sessions');");
      final indexNames = indexList.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_sessions_package_status'));

      final indexInfo = await db.rawQuery("PRAGMA index_info('idx_sessions_package_status');");
      expect(indexInfo.length, equals(2));
      expect(indexInfo[0]['name'], equals('package_name'));
      expect(indexInfo[1]['name'], equals('status'));
    });

    test('verifies query planner uses idx_sessions_package_status for package session lookup', () async {
      final explain = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM block_sessions WHERE package_name = ? AND status = ? ORDER BY start_at DESC LIMIT 1',
        ['com.target.app', BlockSession.statusActive],
      );
      final plan = explain.map((r) => r['detail'].toString()).join(' ');
      expect(plan, contains('USING INDEX idx_sessions_package_status'));
    });

    test('upgrades from v1 directly to v3 idempotently', () async {
      final dbPath = p.join(await getDatabasesPath(), 'test_v1_to_v3_upgrade.db');
      await databaseFactoryFfi.deleteDatabase(dbPath);

      final v1Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE activity_logs (
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
              CREATE TABLE block_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_at INTEGER NOT NULL,
                end_at INTEGER NOT NULL,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL
              );
            ''');
            await db.insert('block_sessions', {
              'start_at': 1000,
              'end_at': 2000,
              'status': 'active',
              'created_at': 1000,
            });
          },
        ),
      );
      await v1Db.close();

      final upgradedDb = await appDatabase.initDatabase(
        customPath: dbPath,
        factory: databaseFactoryFfi,
      );

      final columns = await upgradedDb.rawQuery('PRAGMA table_info(block_sessions);');
      final colNames = columns.map((c) => c['name'] as String).toList();
      expect(colNames, contains('package_name'));

      final indexList = await upgradedDb.rawQuery("PRAGMA index_list('block_sessions');");
      final indexNames = indexList.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_sessions_package_status'));

      final initialRow = await upgradedDb.query('block_sessions');
      expect(initialRow.length, equals(1));
      expect(initialRow.first['package_name'], isNull);

      final testRepo = BlockSessionRepositoryImpl(db: upgradedDb);
      await testRepo.createSession(
        BlockSession(
          packageName: 'com.v1v3.app',
          startAt: DateTime.fromMillisecondsSinceEpoch(5000),
          endAt: DateTime.fromMillisecondsSinceEpoch(6000),
          status: BlockSession.statusActive,
          createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
        ),
      );

      final active = await testRepo.getActiveSessionForPackage('com.v1v3.app');
      expect(active, isNotNull);
      expect(active!.packageName, equals('com.v1v3.app'));

      await databaseFactoryFfi.deleteDatabase(dbPath);
    });
  });

  group('M2 Challenger - Adversarial Boundary & Injection Tests', () {
    test('handles extreme and adversarial package names safely without SQL injection', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(10000000);
      final injectionNames = [
        "com.app'; DROP TABLE block_sessions; --",
        'com.o\'reilly.app',
        'com."quoted".app',
        'com.spaces in package.name',
        'com.unicode.🔥.app',
        '',
        'com.long.${'a' * 5000}.app',
      ];

      for (int i = 0; i < injectionNames.length; i++) {
        final pkg = injectionNames[i];
        final id = await repository.createSession(
          BlockSession(
            packageName: pkg,
            startAt: t0.add(Duration(seconds: i * 10)),
            endAt: t0.add(Duration(seconds: 300 + (i * 10))),
            status: BlockSession.statusActive,
            createdAt: t0.add(Duration(seconds: i * 10)),
          ),
        );
        expect(id, isPositive);
      }

      for (final pkg in injectionNames) {
        final retrieved = await repository.getActiveSessionForPackage(pkg);
        expect(retrieved, isNotNull);
        expect(retrieved!.packageName, equals(pkg));
      }

      final checkTable = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='block_sessions';");
      expect(checkTable.isNotEmpty, isTrue);

      final targetInjection = "com.app'; DROP TABLE block_sessions; --";
      await repository.completeActiveSessionsForPackage(targetInjection);

      expect(await repository.getActiveSessionForPackage(targetInjection), isNull);

      for (final pkg in injectionNames.where((p) => p != targetInjection)) {
        final remaining = await repository.getActiveSessionForPackage(pkg);
        expect(remaining, isNotNull);
        expect(remaining!.packageName, equals(pkg));
      }
    });

    test('enforces SQLite CHECK constraints on status and timestamps', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(20000000);

      expect(
        () async => await db.insert(
          AppDatabase.tableBlockSessions,
          {
            'package_name': 'com.check.status',
            'start_at': t0.millisecondsSinceEpoch,
            'end_at': t0.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
            'status': 'invalid_status_enum',
            'created_at': t0.millisecondsSinceEpoch,
          },
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(
          AppDatabase.tableBlockSessions,
          {
            'package_name': 'com.check.time',
            'start_at': t0.millisecondsSinceEpoch,
            'end_at': t0.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
            'status': BlockSession.statusActive,
            'created_at': t0.millisecondsSinceEpoch,
          },
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () async => await db.insert(
          AppDatabase.tableBlockSessions,
          {
            'package_name': 'com.check.equal',
            'start_at': t0.millisecondsSinceEpoch,
            'end_at': t0.millisecondsSinceEpoch,
            'status': BlockSession.statusActive,
            'created_at': t0.millisecondsSinceEpoch,
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('maintains ON DELETE SET NULL relationship with temporary_unlocks and activity_logs', () async {
      final appId = await db.insert(AppDatabase.tableBlockedApps, {
        'package_name': 'com.fk.test',
        'app_name': 'FK Test',
        'is_selected': 1,
        'created_at': 1000,
      });

      final sessionId = await repository.createSession(
        BlockSession(
          packageName: 'com.fk.test',
          startAt: DateTime.fromMillisecondsSinceEpoch(1000),
          endAt: DateTime.fromMillisecondsSinceEpoch(2000),
          status: BlockSession.statusActive,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );

      final unlockId = await db.insert(AppDatabase.tableTemporaryUnlocks, {
        'app_id': appId,
        'session_id': sessionId,
        'start_at': 1000,
        'end_at': 2000,
        'status': 'active',
        'created_at': 1000,
      });

      final logId = await db.insert(AppDatabase.tableActivityLogs, {
        'app_id': appId,
        'session_id': sessionId,
        'package_name_snapshot': 'com.fk.test',
        'app_name_snapshot': 'FK Test',
        'event_type': 'test_event',
        'attempted_at': 1000,
      });

      await db.delete(
        AppDatabase.tableBlockSessions,
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      final unlockRow = await db.query(
        AppDatabase.tableTemporaryUnlocks,
        where: 'id = ?',
        whereArgs: [unlockId],
      );
      expect(unlockRow.first['session_id'], isNull);

      final logRow = await db.query(
        AppDatabase.tableActivityLogs,
        where: 'id = ?',
        whereArgs: [logId],
      );
      expect(logRow.first['session_id'], isNull);

      final integrity = await appDatabase.verifyIntegrity(full: true, targetDb: db);
      expect(integrity.isHealthy, isTrue);
      expect(integrity.isForeignKeyOk, isTrue);
    });
  });

  group('M2 Challenger - 100 Package High Scale Stress Isolation', () {
    test('100 concurrent packages maintain strict isolation during creation, query, and selective completion', () async {
      final baseEpoch = 30000000;
      final packageCount = 100;
      final packages = List.generate(packageCount, (i) => 'com.scale.app_$i');

      final createFutures = packages.map((pkg) {
        final index = int.parse(pkg.split('_').last);
        return repository.createSession(
          BlockSession(
            packageName: pkg,
            startAt: DateTime.fromMillisecondsSinceEpoch(baseEpoch + (index * 1000)),
            endAt: DateTime.fromMillisecondsSinceEpoch(baseEpoch + (index * 1000) + 300000),
            status: BlockSession.statusActive,
            createdAt: DateTime.fromMillisecondsSinceEpoch(baseEpoch + (index * 1000)),
          ),
        );
      }).toList();

      final createdIds = await Future.wait(createFutures);
      expect(createdIds.length, equals(packageCount));
      expect(createdIds.toSet().length, equals(packageCount));

      final queryFutures = packages.map((pkg) => repository.getActiveSessionForPackage(pkg)).toList();
      final sessions = await Future.wait(queryFutures);

      for (int i = 0; i < packageCount; i++) {
        expect(sessions[i], isNotNull);
        expect(sessions[i]!.packageName, equals(packages[i]));
        expect(sessions[i]!.id, equals(createdIds[i]));
      }

      final evenPackages = packages.where((p) => int.parse(p.split('_').last) % 2 == 0).toList();
      final oddPackages = packages.where((p) => int.parse(p.split('_').last) % 2 != 0).toList();

      final completeFutures = evenPackages.map((pkg) => repository.completeActiveSessionsForPackage(pkg)).toList();
      await Future.wait(completeFutures);

      final evenCheckFutures = evenPackages.map((pkg) => repository.getActiveSessionForPackage(pkg)).toList();
      final evenResults = await Future.wait(evenCheckFutures);
      for (final res in evenResults) {
        expect(res, isNull);
      }

      final oddCheckFutures = oddPackages.map((pkg) => repository.getActiveSessionForPackage(pkg)).toList();
      final oddResults = await Future.wait(oddCheckFutures);
      for (final res in oddResults) {
        expect(res, isNotNull);
        expect(res!.status, equals(BlockSession.statusActive));
      }

      final totalCompleted = await db.query(
        AppDatabase.tableBlockSessions,
        where: 'status = ?',
        whereArgs: [BlockSession.statusCompleted],
      );
      expect(totalCompleted.length, equals(evenPackages.length));
    });

    test('interleaved multiple active and completed sessions for same package order correctly and complete fully', () async {
      final t0 = DateTime.fromMillisecondsSinceEpoch(40000000);
      final pkg = 'com.interleaved.target';

      final id1 = await repository.createSession(
        BlockSession(
          packageName: pkg,
          startAt: t0,
          endAt: t0.add(const Duration(minutes: 5)),
          status: BlockSession.statusActive,
          createdAt: t0,
        ),
      );

      final id2 = await repository.createSession(
        BlockSession(
          packageName: pkg,
          startAt: t0.add(const Duration(minutes: 10)),
          endAt: t0.add(const Duration(minutes: 15)),
          status: BlockSession.statusActive,
          createdAt: t0.add(const Duration(minutes: 10)),
        ),
      );

      final id3 = await repository.createSession(
        BlockSession(
          packageName: pkg,
          startAt: t0.add(const Duration(minutes: 5)),
          endAt: t0.add(const Duration(minutes: 8)),
          status: BlockSession.statusCompleted,
          createdAt: t0.add(const Duration(minutes: 5)),
        ),
      );

      final active = await repository.getActiveSessionForPackage(pkg);
      expect(active, isNotNull);
      expect(active!.id, equals(id2));

      await repository.completeActiveSessionsForPackage(pkg);

      expect(await repository.getActiveSessionForPackage(pkg), isNull);

      final allSessions = await db.query(
        AppDatabase.tableBlockSessions,
        where: 'package_name = ?',
        whereArgs: [pkg],
        orderBy: 'id ASC',
      );
      expect(allSessions.length, equals(3));
      expect(allSessions.every((s) => s['status'] == BlockSession.statusCompleted), isTrue);
      expect(allSessions.map((s) => s['id']), containsAll([id1, id2, id3]));
    });
  });
}
