import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
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
  Future<void> expireOutdatedUnlocks() async {
    final db = await _getDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.update(
      AppDatabase.tableTemporaryUnlocks,
      {'status': TemporaryUnlock.statusExpired},
      where: 'status = ? AND end_at <= ?',
      whereArgs: [TemporaryUnlock.statusActive, now],
    );
  }
}
