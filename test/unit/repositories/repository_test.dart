import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/models.dart';
import 'package:self_control/data/repositories/repositories.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    appDatabase = AppDatabase.instance;
    db = await appDatabase.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('BlockedAppRepository Tests', () {
    late BlockedAppRepository repository;

    setUp(() {
      repository = BlockedAppRepositoryImpl(db: db);
    });

    test('saves, queries, and updates selection status of apps', () async {
      final now = DateTime.now();
      final app1 = BlockedApp(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        isSelected: true,
        createdAt: now,
      );
      final app2 = BlockedApp(
        packageName: 'com.zhiliaoapp.musically',
        appName: 'TikTok',
        isSelected: false,
        createdAt: now,
      );

      await repository.saveApps([app1, app2]);

      final allApps = await repository.getAllApps();
      expect(allApps.length, equals(2));
      expect(allApps[0].appName, equals('Instagram'));
      expect(allApps[1].appName, equals('TikTok'));

      final selectedApps = await repository.getSelectedApps();
      expect(selectedApps.length, equals(1));
      expect(selectedApps.first.packageName, equals('com.instagram.android'));

      final fetched = await repository.getAppByPackageName('com.instagram.android');
      expect(fetched, isNotNull);
      expect(fetched!.appName, equals('Instagram'));

      final nonExistent = await repository.getAppByPackageName('com.unknown');
      expect(nonExistent, isNull);

      await repository.setAppSelected('com.instagram.android', false);
      final updated = await repository.getAppByPackageName('com.instagram.android');
      expect(updated!.isSelected, isFalse);

      final updatedApp = BlockedApp(
        packageName: 'com.instagram.android',
        appName: 'Instagram Updated',
        isSelected: true,
        createdAt: now,
      );
      await repository.saveApps([updatedApp]);

      final rechecked = await repository.getAppByPackageName('com.instagram.android');
      expect(rechecked!.appName, equals('Instagram Updated'));
      expect(rechecked.isSelected, isFalse);
    });
  });

  group('BlockRuleRepository Tests', () {
    late BlockRuleRepository repository;

    setUp(() {
      repository = BlockRuleRepositoryImpl(db: db);
    });

    test('performs full CRUD lifecycle on duration and schedule rules', () async {
      final durationRule = BlockRule.duration(durationMinutes: 45);
      await repository.saveRule(durationRule);

      final scheduleRule = BlockRule.schedule(
        scheduleStartMinute: 1320,
        scheduleEndMinute: 420,
        daysMask: 31,
      );
      await repository.saveRule(scheduleRule);

      final allRules = await repository.getAllRules();
      expect(allRules.length, equals(2));

      final activeRule = await repository.getActiveRule();
      expect(activeRule, isNotNull);

      final firstRule = allRules.first;
      final updatedRule = firstRule.copyWith(durationMinutes: 90);
      await repository.updateRule(updatedRule);

      final rechecked = await repository.getAllRules();
      expect(rechecked.first.durationMinutes, equals(90));

      await repository.deleteRule(firstRule.id!);
      final remaining = await repository.getAllRules();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals(allRules.last.id));
    });
  });

  group('BlockSessionRepository Tests', () {
    late BlockSessionRepository repository;

    setUp(() {
      repository = BlockSessionRepositoryImpl(db: db);
    });

    test('creates sessions, manages active states, and queries scheduled sessions', () async {
      final now = DateTime.now();
      final activeSession = BlockSession(
        startAt: now,
        endAt: now.add(const Duration(hours: 1)),
        status: BlockSession.statusActive,
        createdAt: now,
      );
      final scheduledSession = BlockSession(
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 4)),
        status: BlockSession.statusScheduled,
        createdAt: now,
      );

      final activeId = await repository.createSession(activeSession);
      final scheduledId = await repository.createSession(scheduledSession);

      expect(activeId, isPositive);
      expect(scheduledId, isPositive);

      final currentActive = await repository.getActiveSession();
      expect(currentActive, isNotNull);
      expect(currentActive!.id, equals(activeId));

      final scheduledList = await repository.getScheduledSessions();
      expect(scheduledList.length, equals(1));
      expect(scheduledList.first.id, equals(scheduledId));

      await repository.updateSessionStatus(activeId, BlockSession.statusCompleted);
      final afterCompletion = await repository.getActiveSession();
      expect(afterCompletion, isNull);
    });
  });

  group('TemporaryUnlockRepository Tests', () {
    late TemporaryUnlockRepository repository;
    late BlockedAppRepository appRepo;

    setUp(() {
      repository = TemporaryUnlockRepositoryImpl(db: db);
      appRepo = BlockedAppRepositoryImpl(db: db);
    });

    test('manages temporary unlocks and relational package lookup', () async {
      final now = DateTime.now();
      await appRepo.saveApps([
        BlockedApp(
          packageName: 'com.social.app',
          appName: 'Social App',
          createdAt: now,
        ),
      ]);
      final app = (await appRepo.getAppByPackageName('com.social.app'))!;

      final unlock = TemporaryUnlock(
        appId: app.id!,
        startAt: now.subtract(const Duration(minutes: 1)),
        endAt: now.add(const Duration(minutes: 9)),
        status: TemporaryUnlock.statusActive,
        createdAt: now,
      );

      final unlockId = await repository.createUnlock(unlock);
      expect(unlockId, isPositive);

      final activeByApp = await repository.getActiveUnlockForApp(app.id!);
      expect(activeByApp, isNotNull);
      expect(activeByApp!.id, equals(unlockId));

      final activeByPackage = await repository.getActiveUnlockForPackage('com.social.app');
      expect(activeByPackage, isNotNull);
      expect(activeByPackage!.id, equals(unlockId));

      await repository.updateUnlockStatus(unlockId, TemporaryUnlock.statusRevoked);
      final revoked = await repository.getActiveUnlockForApp(app.id!);
      expect(revoked, isNull);

      final expiredUnlock = TemporaryUnlock(
        appId: app.id!,
        startAt: now.subtract(const Duration(minutes: 20)),
        endAt: now.subtract(const Duration(minutes: 5)),
        status: TemporaryUnlock.statusActive,
        createdAt: now,
      );
      await repository.createUnlock(expiredUnlock);

      await repository.expireOutdatedUnlocks();
      final expiredLookup = await repository.getActiveUnlockForApp(app.id!);
      expect(expiredLookup, isNull);
    });
  });

  group('ActivityLogRepository Tests', () {
    late ActivityLogRepository repository;

    setUp(() {
      repository = ActivityLogRepositoryImpl(db: db);
    });

    test('logs events, queries descending timeline, and computes attempt counts', () async {
      final now = DateTime.now();

      for (int i = 0; i < 5; i++) {
        await repository.logEvent(
          ActivityLog(
            packageNameSnapshot: 'com.game.app',
            appNameSnapshot: 'Game App',
            eventType: ActivityLog.eventBlockedAttempt,
            attemptedAt: now.add(Duration(minutes: i)),
          ),
        );
      }

      await repository.logEvent(
        ActivityLog(
          packageNameSnapshot: 'com.chat.app',
          appNameSnapshot: 'Chat App',
          eventType: ActivityLog.eventBlockedAttempt,
          attemptedAt: now.add(const Duration(minutes: 10)),
        ),
      );

      await repository.logEvent(
        ActivityLog(
          packageNameSnapshot: 'com.chat.app',
          appNameSnapshot: 'Chat App',
          eventType: ActivityLog.eventTemporaryUnlockStarted,
          attemptedAt: now.add(const Duration(minutes: 15)),
        ),
      );

      final pagedLogs = await repository.getLogs(limit: 3, offset: 0);
      expect(pagedLogs.length, equals(3));
      expect(pagedLogs.first.eventType, equals(ActivityLog.eventTemporaryUnlockStarted));

      final attemptCounts = await repository.getAttemptCountsByPackage();
      expect(attemptCounts['com.game.app'], equals(5));
      expect(attemptCounts['com.chat.app'], equals(1));
      expect(attemptCounts.containsKey('com.unknown'), isFalse);

      await repository.clearAllLogs();
      final remainingLogs = await repository.getLogs();
      expect(remainingLogs, isEmpty);
    });
  });

  group('SettingsRepository Tests', () {
    late SettingsRepository repository;

    setUp(() {
      repository = SettingsRepositoryImpl(db: db);
    });

    test('verifies initial seeded default settings', () async {
      final waitDuration = await repository.getWaitingDurationSeconds();
      expect(waitDuration, equals(300));

      final lockMessage = await repository.getCustomLockMessage();
      expect(lockMessage, equals('Tetap fokus pada tujuanmu.'));

      final defaultUnlock = await repository.getDefaultUnlockDurationSeconds();
      expect(defaultUnlock, equals(600));
    });

    test('stores and retrieves arbitrary key-value settings', () async {
      await repository.setSetting('theme_mode', 'dark');
      final value = await repository.getSetting('theme_mode');
      expect(value, equals('dark'));

      await repository.setSetting(AppSetting.keyWaitingDurationSeconds, '120');
      final updatedDuration = await repository.getWaitingDurationSeconds();
      expect(updatedDuration, equals(120));
    });

    test('securely sets, salts, and verifies passwords with SHA-256', () async {
      const password = 'SuperSecretUserPassword123!';

      final beforeSetVerify = await repository.verifyPassword(password);
      expect(beforeSetVerify, isFalse);

      await repository.setPassword(password);

      final salt = await repository.getSetting(AppSetting.keyPasswordSalt);
      final hash = await repository.getSetting(AppSetting.keyPasswordHash);

      expect(salt, isNotNull);
      expect(salt!.length, equals(32));
      expect(hash, isNotNull);
      expect(hash!.length, equals(64));
      expect(hash, isNot(contains(password)));

      final verified = await repository.verifyPassword(password);
      expect(verified, isTrue);

      final wrongPasswordVerified = await repository.verifyPassword('WrongPassword');
      expect(wrongPasswordVerified, isFalse);

      await repository.setPassword('NewPassword456!');
      final newSalt = await repository.getSetting(AppSetting.keyPasswordSalt);
      final newHash = await repository.getSetting(AppSetting.keyPasswordHash);

      expect(newSalt, isNot(equals(salt)));
      expect(newHash, isNot(equals(hash)));
      expect(await repository.verifyPassword('NewPassword456!'), isTrue);
      expect(await repository.verifyPassword(password), isFalse);
    });
  });
}
