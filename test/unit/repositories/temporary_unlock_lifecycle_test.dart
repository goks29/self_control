import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/models/temporary_unlock.dart';
import 'package:self_control/data/repositories/blocked_app_repository_impl.dart';
import 'package:self_control/data/repositories/temporary_unlock_repository_impl.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late TemporaryUnlockRepositoryImpl unlockRepo;
  late BlockedAppRepositoryImpl appRepo;

  setUp(() async {
    appDatabase = AppDatabase.instance;
    db = await appDatabase.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    unlockRepo = TemporaryUnlockRepositoryImpl(db: db);
    appRepo = BlockedAppRepositoryImpl(db: db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('TemporaryUnlock Lifecycle & Audit Trail Tests', () {
    test('expireOutdatedUnlocks marks expired rows and inserts audit logs', () async {
      final now = DateTime.now();
      await appRepo.saveApps([
        BlockedApp(
          packageName: 'com.instagram.android',
          appName: 'Instagram',
          isSelected: true,
          createdAt: now,
        ),
      ]);
      final apps = await appRepo.getAllApps();
      final appId = apps.first.id!;

      final expiredUnlock = TemporaryUnlock(
        appId: appId,
        startAt: now.subtract(const Duration(minutes: 15)),
        endAt: now.subtract(const Duration(minutes: 5)),
        status: TemporaryUnlock.statusActive,
        createdAt: now.subtract(const Duration(minutes: 15)),
      );
      final activeUnlock = TemporaryUnlock(
        appId: appId,
        startAt: now,
        endAt: now.add(const Duration(minutes: 10)),
        status: TemporaryUnlock.statusActive,
        createdAt: now,
      );

      final expiredId = await unlockRepo.createUnlock(expiredUnlock);
      final activeId = await unlockRepo.createUnlock(activeUnlock);

      final expiredPkgs = await unlockRepo.expireOutdatedUnlocks();

      expect(expiredPkgs, contains('com.instagram.android'));

      final expiredCheck = await db.query(
        AppDatabase.tableTemporaryUnlocks,
        where: 'id = ?',
        whereArgs: [expiredId],
      );
      expect(expiredCheck.first['status'], TemporaryUnlock.statusExpired);

      final activeCheck = await db.query(
        AppDatabase.tableTemporaryUnlocks,
        where: 'id = ?',
        whereArgs: [activeId],
      );
      expect(activeCheck.first['status'], TemporaryUnlock.statusActive);

      final logs = await db.query(
        AppDatabase.tableActivityLogs,
        where: 'event_type = ?',
        whereArgs: [ActivityLog.eventTemporaryUnlockExpired],
      );
      expect(logs.length, 1);
      expect(logs.first['package_name_snapshot'], 'com.instagram.android');
      expect(logs.first['app_name_snapshot'], 'Instagram');
    });

    test('expireOutdatedUnlocks returns empty list when no unlocks are expired', () async {
      final now = DateTime.now();
      await appRepo.saveApps([
        BlockedApp(
          packageName: 'com.tiktok.android',
          appName: 'TikTok',
          isSelected: true,
          createdAt: now,
        ),
      ]);
      final apps = await appRepo.getAllApps();
      final appId = apps.first.id!;

      await unlockRepo.createUnlock(
        TemporaryUnlock(
          appId: appId,
          startAt: now,
          endAt: now.add(const Duration(minutes: 5)),
          status: TemporaryUnlock.statusActive,
          createdAt: now,
        ),
      );

      final expiredPkgs = await unlockRepo.expireOutdatedUnlocks();
      expect(expiredPkgs, isEmpty);
    });
  });
}
