import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/focus_task.dart';
import 'task_repository.dart';

class TaskRepositoryImpl implements TaskRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  TaskRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  Future<void> _ensureTable(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${AppDatabase.tableFocusTasks} ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'title TEXT NOT NULL, '
      'is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)), '
      'created_at INTEGER NOT NULL);',
    );
  }

  @override
  Future<List<FocusTask>> getAllTasks() async {
    final db = await _getDb();
    await _ensureTable(db);
    final maps = await db.query(
      AppDatabase.tableFocusTasks,
      orderBy: 'is_completed ASC, created_at DESC',
    );
    return maps.map((m) => FocusTask.fromMap(m)).toList();
  }

  @override
  Future<List<FocusTask>> getPendingTasks() async {
    final db = await _getDb();
    await _ensureTable(db);
    final maps = await db.query(
      AppDatabase.tableFocusTasks,
      where: 'is_completed = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => FocusTask.fromMap(m)).toList();
  }

  @override
  Future<int> addTask(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Task title cannot be empty');
    }
    final db = await _getDb();
    await _ensureTable(db);
    final task = FocusTask(
      title: trimmed,
      isCompleted: false,
      createdAt: DateTime.now(),
    );
    return db.insert(AppDatabase.tableFocusTasks, task.toMap());
  }

  @override
  Future<void> toggleTaskCompletion(int id, bool isCompleted) async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.update(
      AppDatabase.tableFocusTasks,
      {'is_completed': isCompleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteTask(int id) async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.delete(
      AppDatabase.tableFocusTasks,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
