import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/blocked_app.dart';
import 'blocked_app_repository.dart';

class BlockedAppRepositoryImpl implements BlockedAppRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  BlockedAppRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  @override
  Future<List<BlockedApp>> getAllApps() async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockedApps,
      orderBy: 'app_name COLLATE NOCASE ASC',
    );
    return maps.map((m) => BlockedApp.fromMap(m)).toList();
  }

  @override
  Future<List<BlockedApp>> getSelectedApps() async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockedApps,
      where: 'is_selected = ?',
      whereArgs: [1],
      orderBy: 'app_name COLLATE NOCASE ASC',
    );
    return maps.map((m) => BlockedApp.fromMap(m)).toList();
  }

  @override
  Future<BlockedApp?> getAppByPackageName(String packageName) async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockedApps,
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return BlockedApp.fromMap(maps.first);
  }

  @override
  Future<void> saveApps(List<BlockedApp> apps) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      for (final app in apps) {
        final existing = await txn.query(
          AppDatabase.tableBlockedApps,
          columns: ['id', 'is_selected'],
          where: 'package_name = ?',
          whereArgs: [app.packageName],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          await txn.update(
            AppDatabase.tableBlockedApps,
            {'app_name': app.appName},
            where: 'package_name = ?',
            whereArgs: [app.packageName],
          );
        } else {
          await txn.insert(
            AppDatabase.tableBlockedApps,
            app.toMap(),
          );
        }
      }
    });
  }

  @override
  Future<void> setAppSelected(String packageName, bool isSelected) async {
    final db = await _getDb();
    await db.update(
      AppDatabase.tableBlockedApps,
      {'is_selected': isSelected ? 1 : 0},
      where: 'package_name = ?',
      whereArgs: [packageName],
    );
  }
}
