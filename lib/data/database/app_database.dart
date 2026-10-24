import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  static const String dbName = 'self_control.db';
  static const int dbVersion = 1;

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
  }) async {
    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = join(databasesPath, dbName);
    }

    final dbFactory = factory ?? _customFactory ?? databaseFactory;
    _database = await dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _database!;
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {}

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
