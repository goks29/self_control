import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/block_session.dart';
import 'block_session_repository.dart';

class BlockSessionRepositoryImpl implements BlockSessionRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  BlockSessionRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  @override
  Future<BlockSession?> getActiveSession() async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockSessions,
      where: 'status = ?',
      whereArgs: [BlockSession.statusActive],
      orderBy: 'start_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return BlockSession.fromMap(maps.first);
  }

  @override
  Future<int> createSession(BlockSession session) async {
    final db = await _getDb();
    return await db.insert(
      AppDatabase.tableBlockSessions,
      session.toMap(),
    );
  }

  @override
  Future<void> updateSessionStatus(int sessionId, String status) async {
    final db = await _getDb();
    await db.update(
      AppDatabase.tableBlockSessions,
      {'status': status},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  @override
  Future<List<BlockSession>> getScheduledSessions() async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableBlockSessions,
      where: 'status = ?',
      whereArgs: [BlockSession.statusScheduled],
      orderBy: 'start_at ASC',
    );
    return maps.map((m) => BlockSession.fromMap(m)).toList();
  }
}
