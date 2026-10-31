import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/activity_log.dart';
import '../models/temporary_unlock.dart';
import 'temporary_unlock_repository.dart';

class TemporaryUnlockRepositoryImpl implements TemporaryUnlockRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  TemporaryUnlockRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  @override
  Future<TemporaryUnlock?> getActiveUnlockForApp(int appId) async {
    final db = await _getDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final maps = await db.query(
      AppDatabase.tableTemporaryUnlocks,
      where: 'app_id = ? AND status = ? AND end_at > ?',
      whereArgs: [appId, TemporaryUnlock.statusActive, now],
      orderBy: 'end_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TemporaryUnlock.fromMap(maps.first);
  }

  @override
  Future<TemporaryUnlock?> getActiveUnlockForPackage(String packageName) async {
    final db = await _getDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final maps = await db.rawQuery('''
      SELECT tu.* FROM ${AppDatabase.tableTemporaryUnlocks} tu
      INNER JOIN ${AppDatabase.tableBlockedApps} ba ON tu.app_id = ba.id
      WHERE ba.package_name = ? AND tu.status = ? AND tu.end_at > ?
      ORDER BY tu.end_at DESC LIMIT 1;
    ''', [packageName, TemporaryUnlock.statusActive, now]);
    if (maps.isEmpty) return null;
    return TemporaryUnlock.fromMap(maps.first);
  }

  @override
  Future<int> createUnlock(TemporaryUnlock unlock) async {
    final db = await _getDb();
    return await db.insert(
      AppDatabase.tableTemporaryUnlocks,
      unlock.toMap(),
    );
  }

  @override
  Future<void> updateUnlockStatus(int unlockId, String status) async {
    final db = await _getDb();
    await db.update(
      AppDatabase.tableTemporaryUnlocks,
      {'status': status},
      where: 'id = ?',
      whereArgs: [unlockId],
    );
  }

  @override
  Future<List<String>> expireOutdatedUnlocks() async {
    final db = await _getDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    final expiredRows = await db.rawQuery(
      '''
        SELECT tu.id, tu.app_id, ba.package_name, ba.app_name
        FROM ${AppDatabase.tableTemporaryUnlocks} tu
        LEFT JOIN ${AppDatabase.tableBlockedApps} ba ON tu.app_id = ba.id
        WHERE tu.status = ? AND tu.end_at <= ?
      ''',
      [TemporaryUnlock.statusActive, now],
    );

    if (expiredRows.isEmpty) {
      await db.update(
        AppDatabase.tableTemporaryUnlocks,
        {'status': TemporaryUnlock.statusExpired},
        where: 'status = ? AND end_at <= ?',
        whereArgs: [TemporaryUnlock.statusActive, now],
      );
      return <String>[];
    }

    final expiredPackageNames = <String>[];
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in expiredRows) {
        final unlockId = row['id'] as int;
        final appId = row['app_id'] as int?;
        final pkg = row['package_name'] as String?;
        final appName = row['app_name'] as String?;
        if (pkg != null) {
          expiredPackageNames.add(pkg);
        }

        batch.update(
          AppDatabase.tableTemporaryUnlocks,
          {'status': TemporaryUnlock.statusExpired},
          where: 'id = ?',
          whereArgs: [unlockId],
        );

        batch.insert(AppDatabase.tableActivityLogs, {
          'app_id': appId,
          'package_name_snapshot': pkg ?? 'unknown.app',
          'app_name_snapshot': appName ?? 'Aplikasi Dibatasi',
          'event_type': ActivityLog.eventTemporaryUnlockExpired,
          'attempted_at': now,
        });
      }
      await batch.commit(noResult: true);
    });

    return expiredPackageNames;
  }
}
