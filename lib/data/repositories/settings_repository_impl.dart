import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/app_setting.dart';
import 'settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final Database? db;
  final AppDatabase? appDatabase;

  SettingsRepositoryImpl({this.db, this.appDatabase});

  Future<Database> _getDb() async {
    final customDb = db;
    if (customDb != null) return customDb;
    return (appDatabase ?? AppDatabase.instance).database;
  }

  String _generateSalt([int length = 16]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashWithSalt(String plainPassword, String salt) {
    final bytes = utf8.encode('$salt:$plainPassword');
    return sha256.convert(bytes).toString();
  }

  @override
  Future<String?> getSetting(String key) async {
    final db = await _getDb();
    final maps = await db.query(
      AppDatabase.tableAppSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    final db = await _getDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(
      AppDatabase.tableAppSettings,
      {
        'key': key,
        'value': value,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> getWaitingDurationSeconds() async {
    final val = await getSetting(AppSetting.keyWaitingDurationSeconds);
    return int.tryParse(val ?? '') ?? AppSetting.defaultWaitingDurationSeconds;
  }

  @override
  Future<String> getCustomLockMessage() async {
    final val = await getSetting(AppSetting.keyCustomLockMessage);
    return val ?? AppSetting.defaultCustomLockMessage;
  }

  @override
  Future<bool> verifyPassword(String plainPassword) async {
    final salt = await getSetting(AppSetting.keyPasswordSalt);
    final hash = await getSetting(AppSetting.keyPasswordHash);
    if (salt == null || salt.isEmpty || hash == null || hash.isEmpty) {
      return false;
    }
    final calculatedHash = _hashWithSalt(plainPassword, salt);
    return calculatedHash == hash;
  }

  @override
  Future<void> setPassword(String plainPassword) async {
    final salt = _generateSalt();
    final hash = _hashWithSalt(plainPassword, salt);
    final db = await _getDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert(
        AppDatabase.tableAppSettings,
        {
          'key': AppSetting.keyPasswordSalt,
          'value': salt,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        AppDatabase.tableAppSettings,
        {
          'key': AppSetting.keyPasswordHash,
          'value': hash,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<int> getDefaultUnlockDurationSeconds() async {
    final val = await getSetting(AppSetting.keyDefaultUnlockDurationSeconds);
    return int.tryParse(val ?? '') ?? AppSetting.defaultUnlockDurationSeconds;
  }
}
