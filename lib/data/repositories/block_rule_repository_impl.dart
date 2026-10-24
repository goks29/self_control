import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/block_rule.dart';
import 'block_rule_repository.dart';

class BlockRuleRepositoryImpl implements BlockRuleRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  BlockRuleRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  @override
  Future<List<BlockRule>> getAllRules() async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockRules,
      orderBy: 'id ASC',
    );
    return maps.map((m) => BlockRule.fromMap(m)).toList();
  }

  @override
  Future<BlockRule?> getActiveRule() async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockRules,
      where: 'is_enabled = ?',
      whereArgs: [1],
      orderBy: 'id ASC',
    );
    if (maps.isEmpty) return null;

    final rules = maps.map((m) => BlockRule.fromMap(m)).toList();
    final now = DateTime.now();

    for (final rule in rules) {
      if (rule.isDurationMode || rule.isActiveAt(now)) {
        return rule;
      }
    }
    return rules.first;
  }

  @override
  Future<void> saveRule(BlockRule rule) async {
    final db = await _getDb();
    if (rule.id == null) {
      await db.insert(AppDatabase.tableBlockRules, rule.toMap());
    } else {
      await db.insert(
        AppDatabase.tableBlockRules,
        rule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<void> updateRule(BlockRule rule) async {
    final db = await _getDb();
    final map = rule.toMap();
    map['updated_at'] = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.update(
      AppDatabase.tableBlockRules,
      map,
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  @override
  Future<void> deleteRule(int id) async {
    final db = await _getDb();
    await db.delete(
      AppDatabase.tableBlockRules,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
