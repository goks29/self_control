import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/activity_log.dart';
import 'activity_log_repository.dart';

class ActivityLogRepositoryImpl implements ActivityLogRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  ActivityLogRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  @override
  Future<void> logEvent(ActivityLog log) async {
    final db = await _getDb();
    await db.insert(
      AppDatabase.tableActivityLogs,
      log.toMap(),
    );
  }

  @override
  Future<List<ActivityLog>> getLogs({int? limit, int? offset}) async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableActivityLogs,
      orderBy: 'attempted_at DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => ActivityLog.fromMap(m)).toList();
  }

  @override
  Future<Map<String, int>> getAttemptCountsByPackage({String? outcome = ActivityLog.outcomeConfirmed}) async {
    final db = await _getDb();
    final List<Map<String, Object?>> results;
    if (outcome != null) {
      results = await db.rawQuery('''
        SELECT package_name_snapshot, COUNT(*) AS attempt_count
        FROM ${AppDatabase.tableActivityLogs}
        WHERE event_type = ? AND outcome = ?
        GROUP BY package_name_snapshot
        ORDER BY attempt_count DESC;
      ''', [ActivityLog.eventBlockedAttempt, outcome]);
    } else {
      results = await db.rawQuery('''
        SELECT package_name_snapshot, COUNT(*) AS attempt_count
        FROM ${AppDatabase.tableActivityLogs}
        WHERE event_type = ?
        GROUP BY package_name_snapshot
        ORDER BY attempt_count DESC;
      ''', [ActivityLog.eventBlockedAttempt]);
    }

    final map = <String, int>{};
    for (final row in results) {
      final pkg = row['package_name_snapshot'] as String;
      final count = row['attempt_count'] as int;
      map[pkg] = count;
    }
    return map;
  }

  @override
  Future<Map<String, int>> getOutcomeCounts() async {
    final db = await _getDb();
    final results = await db.rawQuery('''
      SELECT outcome, COUNT(*) AS total_count
      FROM ${AppDatabase.tableActivityLogs}
      GROUP BY outcome;
    ''');

    final map = <String, int>{};
    for (final row in results) {
      final outcome = (row['outcome'] as String?) ?? ActivityLog.outcomeUnknown;
      final count = row['total_count'] as int;
      map[outcome] = count;
    }
    return map;
  }

  @override
  Future<void> clearAllLogs() async {
    final db = await _getDb();
    await db.delete(AppDatabase.tableActivityLogs);
  }
}
