import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:self_control/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SqliteFailure implements DatabaseException {
  _SqliteFailure(this.code);
  final int? code;
  @override
  int? getResultCode() => code;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingFactory implements DatabaseFactory {
  _FailingFactory(this.error);
  final Object error;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryProbe extends AppDatabase {
  bool recoveryAttempted = false;
  @override
  Future<Database> performFailsafeRecovery({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    recoveryAttempted = true;
    throw StateError('recovery attempted');
  }
}

class _IntegrityProbe extends AppDatabase {
  bool failCheck = true;
  bool recoveryAttempted = false;
  Object? checkError;
  Database? checkedDatabase;
  @override
  Future<DatabaseIntegrityResult> verifyIntegrity({
    bool full = false,
    Database? targetDb,
  }) async {
    checkedDatabase = targetDb;
    if (checkError != null) throw checkError!;
    return DatabaseIntegrityResult(
      isHealthy: !failCheck,
      isIntegrityOk: !failCheck,
      isForeignKeyOk: true,
    );
  }

  @override
  Future<Database> performFailsafeRecovery({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    recoveryAttempted = true;
    await close();
    failCheck = false;
    return initDatabase(
      customPath: customPath,
      factory: factory,
      enableAutoRecovery: false,
    );
  }
}

class _MigrationFactory implements DatabaseFactory {
  _MigrationFactory(this.error);
  final Object error;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    await options!.onUpgrade!(_QueryDatabase(error: error), 1, 3);
    throw StateError('unreachable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QueryDatabase implements Database {
  _QueryDatabase({this.error, this.rows = const []});
  final Object? error;
  final List<Map<String, Object?>> rows;
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    throw error!;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => rows;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'migration callback failures never recover even with corruption codes',
    () async {
      final error = _SqliteFailure(11);
      final db = _RecoveryProbe();
      await expectLater(
        db.initDatabase(
          customPath: inMemoryDatabasePath,
          factory: _MigrationFactory(error),
        ),
        throwsA(same(error)),
      );
      expect(db.recoveryAttempted, isFalse);
    },
  );

  test('disabled recovery propagates confirmed corruption', () async {
    final error = _SqliteFailure(26);
    final db = _RecoveryProbe();
    await expectLater(
      db.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: _FailingFactory(error),
        enableAutoRecovery: false,
      ),
      throwsA(same(error)),
    );
    expect(db.recoveryAttempted, isFalse);
    expect(db.recoveredOnOpen, isFalse);
  });

  test('quick check reads every row, not just an initial ok', () async {
    final result = await AppDatabase().verifyIntegrity(
      targetDb: _QueryDatabase(
        rows: [
          {'quick_check': 'ok'},
          {'quick_check': 'page 3 is corrupt'},
        ],
      ),
    );
    expect(result.isHealthy, isFalse);
    expect(result.integrityErrors, ['page 3 is corrupt']);
  });

  test('empty integrity output is not healthy', () async {
    final result = await AppDatabase().verifyIntegrity(
      full: true,
      targetDb: _QueryDatabase(),
    );
    expect(result.isHealthy, isFalse);
    expect(result.integrityErrors, isNotEmpty);
  });

  test('recovery flag is true only after successful recreation', () async {
    final dir = Directory.systemTemp.createTempSync('recovery_flag_');
    final path = p.join(dir.path, 'data.db');
    File(path).writeAsStringSync('not sqlite');
    final db = AppDatabase();
    addTearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
    expect(db.recoveredOnOpen, isFalse);
    await db.initDatabase(customPath: path, factory: databaseFactoryFfi);
    expect(db.recoveredOnOpen, isTrue);
    await db.close();
    await db.initDatabase(customPath: path, factory: databaseFactoryFfi);
    expect(db.recoveredOnOpen, isFalse);
    await db.resetToDefaults();
    expect(db.recoveredOnOpen, isFalse);
  });

  for (final error in <Object>[
    StateError('migration failed'),
    FileSystemException('permission denied'),
    _SqliteFailure(null),
    _SqliteFailure(1),
    _SqliteFailure(8),
    _SqliteFailure(14),
  ]) {
    test(
      'does not recover unknown, migration, or permission error: $error',
      () async {
        final db = _RecoveryProbe();
        await expectLater(
          db.initDatabase(
            customPath: inMemoryDatabasePath,
            factory: _FailingFactory(error),
          ),
          throwsA(same(error)),
        );
        expect(db.recoveryAttempted, isFalse);
      },
    );
  }

  for (final code in [11, 26, 267]) {
    test('recovers confirmed SQLite corruption code $code', () async {
      final db = _RecoveryProbe();
      await expectLater(
        db.initDatabase(
          customPath: inMemoryDatabasePath,
          factory: _FailingFactory(_SqliteFailure(code)),
        ),
        throwsStateError,
      );
      expect(db.recoveryAttempted, isTrue);
    });
  }

  test('failed integrity result triggers recovery', () async {
    final db = _IntegrityProbe();
    addTearDown(db.close);
    await db.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    expect(db.recoveryAttempted, isTrue);
    expect(db.recoveredOnOpen, isTrue);
  });

  test(
    'unknown integrity exception is not corruption and is not cached',
    () async {
      final db = _IntegrityProbe()
        ..checkError = StateError('check unavailable');
      addTearDown(db.close);
      await expectLater(
        db.initDatabase(
          customPath: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
        throwsA(same(db.checkError)),
      );
      expect(db.recoveryAttempted, isFalse);
      expect(db.checkedDatabase!.isOpen, isFalse);
      expect(db.recoveredOnOpen, isFalse);
    },
  );

  test(
    'failed migration preserves original database and data without backup',
    () async {
      final dir = Directory.systemTemp.createTempSync('migration_safety_');
      final path = p.join(dir.path, 'data.db');
      final appDb = AppDatabase();
      addTearDown(() async {
        await appDb.close();
        dir.deleteSync(recursive: true);
      });
      final oldDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) =>
              db.execute('CREATE TABLE user_data (value TEXT);'),
        ),
      );
      await oldDb.insert('user_data', {'value': 'preserve me'});
      await oldDb.close();
      await expectLater(
        appDb.initDatabase(customPath: path, factory: databaseFactoryFfi),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        dir.listSync().where((f) => f.path.contains('.corrupt.')),
        isEmpty,
      );
      final preserved = await databaseFactoryFfi.openDatabase(path);
      try {
        expect(
          (await preserved.query('user_data')).single['value'],
          'preserve me',
        );
        expect(await preserved.getVersion(), 1);
      } finally {
        await preserved.close();
      }
    },
  );
}
