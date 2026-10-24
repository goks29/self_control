import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/block_rule.dart';
import 'package:self_control/data/models/app_setting.dart';
import 'package:self_control/data/repositories/settings_repository.dart';
import 'package:self_control/data/repositories/settings_repository_impl.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Adversarial Sweep: BlockRule.isActiveAt 1,440-Minute Daily Sweep', () {
    // 2026-10-19 is a Monday (weekday 1)
    // 2026-10-20 is a Tuesday (weekday 2)
    // 2026-10-21 is a Wednesday (weekday 3)
    // 2026-10-22 is a Thursday (weekday 4)
    // 2026-10-23 is a Friday (weekday 5)
    // 2026-10-24 is a Saturday (weekday 6)
    // 2026-10-25 is a Sunday (weekday 7)
    final mondayBase = DateTime(2026, 10, 19, 0, 0);

    test('Overnight Schedule (22:00 to 07:00, Monday Only, mask = 1) across all 10,080 minutes of the week', () {
      final rule = BlockRule.schedule(
        scheduleStartMinute: 1320, // 22:00
        scheduleEndMinute: 420,   // 07:00
        daysMask: BlockRule.dayMonday, // 1
      );

      // Verify specific boundary minutes requested
      // Monday 21:59 (false), 22:00 (true), 23:59 (true)
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 21, 59)), isFalse);
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 22, 0)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 23, 59)), isTrue);

      // Tuesday 00:00 (true), 06:59 (true), 07:00 (false), Tuesday 22:00 (false)
      expect(rule.isActiveAt(DateTime(2026, 10, 20, 0, 0)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 20, 6, 59)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 20, 7, 0)), isFalse);
      expect(rule.isActiveAt(DateTime(2026, 10, 20, 22, 0)), isFalse);

      int activeMinutesCount = 0;

      // Exhaustive sweep: 7 days * 1,440 minutes = 10,080 minutes
      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final dayStart = mondayBase.add(Duration(days: dayOffset));
        final weekday = dayStart.weekday;

        for (int minute = 0; minute < 1440; minute++) {
          final dt = dayStart.add(Duration(minutes: minute));
          final isActive = rule.isActiveAt(dt);

          if (isActive) {
            activeMinutesCount++;
          }

          // Oracle definition:
          // Active ONLY when:
          // 1. Monday (weekday 1) from 22:00 (minute 1320) to 23:59 (minute 1439)
          // 2. Tuesday (weekday 2) from 00:00 (minute 0) to 06:59 (minute 419)
          final bool expectedActive;
          if (weekday == DateTime.monday && minute >= 1320) {
            expectedActive = true;
          } else if (weekday == DateTime.tuesday && minute < 420) {
            expectedActive = true;
          } else {
            expectedActive = false;
          }

          expect(
            isActive,
            equals(expectedActive),
            reason: 'Failed at weekday $weekday (${dt.toIso8601String()}), minute $minute',
          );
        }
      }

      // Exact count: (1440 - 1320) + 420 = 120 + 420 = 540 minutes active out of 10,080
      expect(activeMinutesCount, equals(540));
    });

    test('Sunday-to-Monday rollover (Sunday 23:00 to Monday 05:00, mask = 64) across all 10,080 minutes', () {
      final rule = BlockRule.schedule(
        scheduleStartMinute: 1380, // 23:00
        scheduleEndMinute: 300,   // 05:00
        daysMask: BlockRule.daySunday, // 64
      );

      // Boundary tests
      // Sunday 22:59 (false), 23:00 (true), 23:59 (true)
      expect(rule.isActiveAt(DateTime(2026, 10, 25, 22, 59)), isFalse);
      expect(rule.isActiveAt(DateTime(2026, 10, 25, 23, 0)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 25, 23, 59)), isTrue);

      // Monday 00:00 (true), 04:59 (true), 05:00 (false), Monday 23:00 (false)
      expect(rule.isActiveAt(DateTime(2026, 10, 26, 0, 0)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 26, 4, 59)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 26, 5, 0)), isFalse);
      expect(rule.isActiveAt(DateTime(2026, 10, 26, 23, 0)), isFalse);

      int activeMinutesCount = 0;

      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final dayStart = mondayBase.add(Duration(days: dayOffset));
        final weekday = dayStart.weekday;

        for (int minute = 0; minute < 1440; minute++) {
          final dt = dayStart.add(Duration(minutes: minute));
          final isActive = rule.isActiveAt(dt);

          if (isActive) {
            activeMinutesCount++;
          }

          final bool expectedActive;
          if (weekday == DateTime.sunday && minute >= 1380) {
            expectedActive = true;
          } else if (weekday == DateTime.monday && minute < 300) {
            expectedActive = true;
          } else {
            expectedActive = false;
          }

          expect(
            isActive,
            equals(expectedActive),
            reason: 'Sunday rollover failed at weekday $weekday, minute $minute',
          );
        }
      }

      // Sunday 23:00-23:59 (60 mins) + Monday 00:00-04:59 (300 mins) = 360 minutes
      expect(activeMinutesCount, equals(360));
    });

    test('All 7 days mask (127) with overnight schedule (22:00 to 07:00) across all 10,080 minutes', () {
      final rule = BlockRule.schedule(
        scheduleStartMinute: 1320, // 22:00
        scheduleEndMinute: 420,   // 07:00
        daysMask: BlockRule.allDaysMask, // 127
      );

      int activeMinutesCount = 0;

      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final dayStart = mondayBase.add(Duration(days: dayOffset));
        final weekday = dayStart.weekday;

        for (int minute = 0; minute < 1440; minute++) {
          final dt = dayStart.add(Duration(minutes: minute));
          final isActive = rule.isActiveAt(dt);

          if (isActive) {
            activeMinutesCount++;
          }

          // Active every day from 00:00 to 06:59 (rollover from yesterday)
          // and from 22:00 to 23:59 (today's evening)
          final expectedActive = (minute < 420) || (minute >= 1320);

          expect(
            isActive,
            equals(expectedActive),
            reason: 'All days mask failed at weekday $weekday, minute $minute',
          );
        }
      }

      // 540 minutes per day * 7 days = 3,780 minutes
      expect(activeMinutesCount, equals(3780));
    });

    test('Single day mask (1) Daytime schedule (09:00 to 17:00) across all 10,080 minutes', () {
      final rule = BlockRule.schedule(
        scheduleStartMinute: 540,  // 09:00
        scheduleEndMinute: 1020,  // 17:00
        daysMask: BlockRule.dayMonday, // 1
      );

      // Exact boundaries
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 8, 59)), isFalse);
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 9, 0)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 16, 59)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 17, 0)), isFalse);

      int activeMinutesCount = 0;

      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final dayStart = mondayBase.add(Duration(days: dayOffset));
        final weekday = dayStart.weekday;

        for (int minute = 0; minute < 1440; minute++) {
          final dt = dayStart.add(Duration(minutes: minute));
          final isActive = rule.isActiveAt(dt);

          if (isActive) {
            activeMinutesCount++;
          }

          final expectedActive = (weekday == DateTime.monday) && (minute >= 540 && minute < 1020);

          expect(
            isActive,
            equals(expectedActive),
            reason: 'Single day daytime failed at weekday $weekday, minute $minute',
          );
        }
      }

      // Exactly 8 hours = 480 minutes
      expect(activeMinutesCount, equals(480));
    });

    test('Edge Case: Single-minute overnight schedule (23:59 to 00:01, mask = 1)', () {
      final rule = BlockRule.schedule(
        scheduleStartMinute: 1439, // 23:59
        scheduleEndMinute: 1,     // 00:01
        daysMask: BlockRule.dayMonday, // 1
      );

      // Monday 23:58 (false), Monday 23:59 (true)
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 23, 58)), isFalse);
      expect(rule.isActiveAt(DateTime(2026, 10, 19, 23, 59)), isTrue);

      // Tuesday 00:00 (true), Tuesday 00:01 (false)
      expect(rule.isActiveAt(DateTime(2026, 10, 20, 0, 0)), isTrue);
      expect(rule.isActiveAt(DateTime(2026, 10, 20, 0, 1)), isFalse);
    });

    test('Edge Case: Inactive when isEnabled is false or daysMask is 0', () {
      final disabledRule = BlockRule.schedule(
        scheduleStartMinute: 0,
        scheduleEndMinute: 1439,
        daysMask: BlockRule.allDaysMask,
        isEnabled: false,
      );

      final zeroMaskRule = BlockRule.schedule(
        scheduleStartMinute: 0,
        scheduleEndMinute: 1439,
        daysMask: 0,
      );

      for (int minute = 0; minute < 1440; minute++) {
        final dt = mondayBase.add(Duration(minutes: minute));
        expect(disabledRule.isActiveAt(dt), isFalse);
        expect(zeroMaskRule.isActiveAt(dt), isFalse);
      }
    });
  });

  group('Adversarial Stress: SettingsRepositoryImpl Password Security', () {
    late AppDatabase appDatabase;
    late Database db;
    late SettingsRepository repository;

    setUp(() async {
      appDatabase = AppDatabase.instance;
      db = await appDatabase.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      repository = SettingsRepositoryImpl(db: db);
    });

    tearDown(() async {
      await appDatabase.close();
    });

    test('Empty password handling', () async {
      const emptyPassword = '';
      await repository.setPassword(emptyPassword);

      final salt = await repository.getSetting(AppSetting.keyPasswordSalt);
      final hash = await repository.getSetting(AppSetting.keyPasswordHash);

      expect(salt, isNotNull);
      expect(salt!.length, equals(32));
      expect(hash, isNotNull);
      expect(hash!.length, equals(64));

      expect(await repository.verifyPassword(''), isTrue);
      expect(await repository.verifyPassword(' '), isFalse);
      expect(await repository.verifyPassword('a'), isFalse);
    });

    test('Long password handling (10,000 characters)', () async {
      final longPassword = 'A' * 10000;
      await repository.setPassword(longPassword);

      expect(await repository.verifyPassword(longPassword), isTrue);
      expect(await repository.verifyPassword('${longPassword}B'), isFalse);
      expect(await repository.verifyPassword('A' * 9999), isFalse);
    });

    test('Unicode, multi-byte, emojis, and special injection character strings', () async {
      final testCases = <String>[
        '🔥SelfControl🛡️2026',
        '密码_中文_测试_123!@#',
        'كلمة المرور الآمنة 🔒',
        'Пароль123!@#_кириллица',
        "admin'--",
        "'; DROP TABLE app_settings; --",
        'newline\nand\ttab\r\ncharacters',
        'Zalgo t̷e̷s̷t̷ c̷h̷a̷r̷a̷c̷t̷e̷r̷s̷',
        'NullByteTest\u0000InMiddle',
      ];

      for (final password in testCases) {
        await repository.setPassword(password);
        expect(await repository.verifyPassword(password), isTrue, reason: 'Failed to verify $password');
        expect(await repository.verifyPassword('$password!'), isFalse);
      }
    });

    test('Salt randomness: 100 calls with identical password produce distinct salts and hashes', () async {
      const password = 'ConstantAdversarialPassword2026!';
      final salts = <String>{};
      final hashes = <String>{};
      final hexRegex = RegExp(r'^[0-9a-f]+$');

      for (int i = 0; i < 100; i++) {
        await repository.setPassword(password);
        final salt = (await repository.getSetting(AppSetting.keyPasswordSalt))!;
        final hash = (await repository.getSetting(AppSetting.keyPasswordHash))!;

        expect(salt.length, equals(32), reason: 'Salt must be 16 bytes (32 hex characters)');
        expect(hash.length, equals(64), reason: 'Hash must be SHA-256 (64 hex characters)');
        expect(hexRegex.hasMatch(salt), isTrue, reason: 'Salt must be valid lowercase hex');
        expect(hexRegex.hasMatch(hash), isTrue, reason: 'Hash must be valid lowercase hex');

        salts.add(salt);
        hashes.add(hash);

        expect(await repository.verifyPassword(password), isTrue);
      }

      // Absolute randomness: 100 iterations must yield 100 distinct salts and 100 distinct hashes
      expect(salts.length, equals(100), reason: 'Detected salt collision or lack of entropy!');
      expect(hashes.length, equals(100), reason: 'Detected hash collision!');
    });

    test('Unset or empty password state in database fails safely without exceptions', () async {
      // Clear password settings
      await db.delete(
        AppDatabase.tableAppSettings,
        where: 'key IN (?, ?)',
        whereArgs: [AppSetting.keyPasswordSalt, AppSetting.keyPasswordHash],
      );

      expect(await repository.verifyPassword('anyPassword'), isFalse);
      expect(await repository.verifyPassword(''), isFalse);

      // Empty string values
      await repository.setSetting(AppSetting.keyPasswordSalt, '');
      await repository.setSetting(AppSetting.keyPasswordHash, '');

      expect(await repository.verifyPassword('anyPassword'), isFalse);
      expect(await repository.verifyPassword(''), isFalse);
    });
  });
}
