import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/platform/blocking_platform_channel.dart';

class DatabaseIntegrityResult {
  final bool isHealthy;
  final bool isIntegrityOk;
  final bool isForeignKeyOk;
  final List<String> integrityErrors;
  final List<String> foreignKeyViolations;

  const DatabaseIntegrityResult({
    required this.isHealthy,
    required this.isIntegrityOk,
    required this.isForeignKeyOk,
    this.integrityErrors = const [],
    this.foreignKeyViolations = const [],
  });
}

class AppDatabase {
  AppDatabase();
  static final AppDatabase instance = AppDatabase();

  static const String dbName = 'self_control.db';
  static const int dbVersion = 2;

  static const String tableBlockedApps = 'blocked_apps';
  static const String tableBlockRules = 'block_rules';
  static const String tableBlockSessions = 'block_sessions';
  static const String tableTemporaryUnlocks = 'temporary_unlocks';
  static const String tableActivityLogs = 'activity_logs';
  static const String tableAppSettings = 'app_settings';

  Database? _database;
  DatabaseFactory? _customFactory;

  void setCustomFactory(DatabaseFactory? factory) {
    _customFactory = factory;
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase({
    String? customPath,
    DatabaseFactory? factory,
    bool enableAutoRecovery = true,
  }) async {
    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, dbName);
    }

    final dbFactory = factory ?? _customFactory ?? databaseFactory;
    try {
      _database = await dbFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: dbVersion,
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
      final check = await verifyIntegrity(full: false, targetDb: _database);
      if (!check.isHealthy) {
        throw StateError('Database integrity check failed');
      }
      return _database!;
    } catch (e) {
      if (enableAutoRecovery) {
        return performFailsafeRecovery(
          customPath: path,
          factory: dbFactory,
        );
      }
      rethrow;
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE $tableBlockedApps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT NOT NULL UNIQUE,
        app_name TEXT NOT NULL,
        is_selected INTEGER NOT NULL DEFAULT 1 CHECK (is_selected IN (0, 1)),
        created_at INTEGER NOT NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE $tableBlockRules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mode TEXT NOT NULL CHECK (mode IN ('duration', 'schedule')),
        duration_minutes INTEGER,
        schedule_start_minute INTEGER,
        schedule_end_minute INTEGER,
        days_mask INTEGER,
        is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        CHECK (
          (mode = 'duration' AND duration_minutes > 0)
          OR
          (mode = 'schedule' 
            AND schedule_start_minute BETWEEN 0 AND 1439 
            AND schedule_end_minute BETWEEN 0 AND 1439 
            AND schedule_start_minute <> schedule_end_minute 
            AND days_mask BETWEEN 1 AND 127)
        )
      );
    ''');

    batch.execute('''
      CREATE TABLE $tableBlockSessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_at INTEGER NOT NULL,
        end_at INTEGER NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled')),
        created_at INTEGER NOT NULL,
        CHECK (end_at > start_at)
      );
    ''');

    batch.execute('''
      CREATE TABLE $tableTemporaryUnlocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_id INTEGER NOT NULL,
        session_id INTEGER,
        start_at INTEGER NOT NULL,
        end_at INTEGER NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'revoked')),
        created_at INTEGER NOT NULL,
        CHECK (end_at > start_at),
        FOREIGN KEY (app_id) REFERENCES $tableBlockedApps(id) ON DELETE RESTRICT,
        FOREIGN KEY (session_id) REFERENCES $tableBlockSessions(id) ON DELETE SET NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE $tableActivityLogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_id INTEGER,
        session_id INTEGER,
        package_name_snapshot TEXT NOT NULL,
        app_name_snapshot TEXT NOT NULL,
        event_type TEXT NOT NULL,
        outcome TEXT NOT NULL DEFAULT 'confirmed',
        details TEXT,
        attempted_at INTEGER NOT NULL,
        FOREIGN KEY (app_id) REFERENCES $tableBlockedApps(id) ON DELETE SET NULL,
        FOREIGN KEY (session_id) REFERENCES $tableBlockSessions(id) ON DELETE SET NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE $tableAppSettings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    batch.execute('CREATE INDEX idx_logs_attempted_at ON $tableActivityLogs(attempted_at);');
    batch.execute('CREATE INDEX idx_logs_package_time ON $tableActivityLogs(package_name_snapshot, attempted_at);');
    batch.execute('CREATE INDEX idx_logs_outcome ON $tableActivityLogs(outcome);');
    batch.execute('CREATE INDEX idx_sessions_status ON $tableBlockSessions(status);');
    batch.execute('CREATE INDEX idx_unlocks_app_status ON $tableTemporaryUnlocks(app_id, status);');

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    batch.insert(tableAppSettings, {
      'key': 'waiting_duration_seconds',
      'value': '300',
      'updated_at': now,
    });
    batch.insert(tableAppSettings, {
      'key': 'custom_lock_message',
      'value': 'Tetap fokus pada tujuanmu.',
      'updated_at': now,
    });
    batch.insert(tableAppSettings, {
      'key': 'default_unlock_duration_seconds',
      'value': '600',
      'updated_at': now,
    });
    batch.insert(tableAppSettings, {
      'key': 'password_hash',
      'value': '',
      'updated_at': now,
    });
    batch.insert(tableAppSettings, {
      'key': 'password_salt',
      'value': '',
      'updated_at': now,
    });

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableActivityLogs ADD COLUMN outcome TEXT NOT NULL DEFAULT "confirmed";');
      await db.execute('ALTER TABLE $tableActivityLogs ADD COLUMN details TEXT;');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_outcome ON $tableActivityLogs(outcome);');
    }
  }

  Future<DatabaseIntegrityResult> verifyIntegrity({
    bool full = false,
    Database? targetDb,
  }) async {
    final activeDb = targetDb ?? (await database);
    if (!full) {
      final quickCheck = await activeDb.rawQuery('PRAGMA quick_check;');
      final firstRow = quickCheck.isNotEmpty ? quickCheck.first : <String, dynamic>{};
      final status = firstRow.values.isNotEmpty ? firstRow.values.first.toString() : '';
      final isOk = status.toLowerCase() == 'ok';
      return DatabaseIntegrityResult(
        isHealthy: isOk,
        isIntegrityOk: isOk,
        isForeignKeyOk: true,
        integrityErrors: isOk ? const [] : [status],
      );
    }

    final integrityRows = await activeDb.rawQuery('PRAGMA integrity_check;');
    final integrityErrors = <String>[];
    for (final row in integrityRows) {
      final val = row.values.isNotEmpty ? row.values.first.toString() : '';
      if (val.toLowerCase() != 'ok') {
        integrityErrors.add(val);
      }
    }

    final fkRows = await activeDb.rawQuery('PRAGMA foreign_key_check;');
    final fkViolations = <String>[];
    for (final row in fkRows) {
      fkViolations.add(row.toString());
    }

    final isIntegrityOk = integrityErrors.isEmpty;
    final isForeignKeyOk = fkViolations.isEmpty;
    return DatabaseIntegrityResult(
      isHealthy: isIntegrityOk && isForeignKeyOk,
      isIntegrityOk: isIntegrityOk,
      isForeignKeyOk: isForeignKeyOk,
      integrityErrors: integrityErrors,
      foreignKeyViolations: fkViolations,
    );
  }

  void backupCorruptFiles(String dbPath, int timestamp) {
    if (dbPath != inMemoryDatabasePath && !dbPath.startsWith(':memory:')) {
      final mainFile = File(dbPath);
      if (mainFile.existsSync()) {
        mainFile.renameSync('$dbPath.corrupt.$timestamp');
      }
      final walFile = File('$dbPath-wal');
      if (walFile.existsSync()) {
        walFile.renameSync('$dbPath-wal.corrupt.$timestamp');
      }
      final journalFile = File('$dbPath-journal');
      if (journalFile.existsSync()) {
        journalFile.renameSync('$dbPath-journal.corrupt.$timestamp');
      }
      final shmFile = File('$dbPath-shm');
      if (shmFile.existsSync()) {
        try {
          shmFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<Database> performFailsafeRecovery({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    await close();
    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, dbName);
    }
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    backupCorruptFiles(path, timestamp);

    final db = await initDatabase(
      customPath: path,
      factory: factory,
      enableAutoRecovery: false,
    );

    try {
      await db.insert(tableActivityLogs, {
        'package_name_snapshot': 'system',
        'app_name_snapshot': 'AppDatabase',
        'event_type': 'failsafe_recovery',
        'outcome': 'confirmed',
        'details': 'database_recreated_after_corruption',
        'attempted_at': timestamp,
      });
    } catch (_) {}

    try {
      final channel = BlockingPlatformChannel();
      await channel.syncBlockedApps([]);
      await channel.syncActiveSessions(isStrictSessionActive: false);
    } catch (_) {}

    return db;
  }

  Future<Database> resetToDefaults({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    await close();
    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, dbName);
    }
    final dbFactory = factory ?? _customFactory ?? databaseFactory;
    await dbFactory.deleteDatabase(path);

    final db = await initDatabase(
      customPath: path,
      factory: factory,
      enableAutoRecovery: false,
    );

    try {
      final channel = BlockingPlatformChannel();
      await channel.syncBlockedApps([]);
      await channel.syncActiveSessions(isStrictSessionActive: false);
    } catch (_) {}

    return db;
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> deleteDb({String? customPath}) async {
    await close();
    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, dbName);
    }
    final dbFactory = _customFactory ?? databaseFactory;
    await dbFactory.deleteDatabase(path);
  }
}
