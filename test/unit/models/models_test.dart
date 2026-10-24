import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/models.dart';

void main() {
  group('BlockedApp Model Tests', () {
    test('serialization, copyWith, and equality', () {
      final now = DateTime(2026, 10, 24, 12, 0);
      final app = BlockedApp(
        id: 1,
        packageName: 'com.test.app',
        appName: 'Test App',
        isSelected: true,
        createdAt: now,
      );

      final map = app.toMap();
      final fromMap = BlockedApp.fromMap(map);
      expect(fromMap, equals(app));
      expect(fromMap.hashCode, equals(app.hashCode));
      expect(fromMap.toString(), contains('com.test.app'));

      final modified = app.copyWith(appName: 'Renamed App', isSelected: false);
      expect(modified.appName, equals('Renamed App'));
      expect(modified.isSelected, isFalse);
      expect(modified, isNot(equals(app)));
    });
  });

  group('BlockSession Model Tests', () {
    test('status getters, isActiveAt, remainingDuration, and serialization', () {
      final start = DateTime(2026, 10, 24, 10, 0);
      final end = DateTime(2026, 10, 24, 11, 0);
      final session = BlockSession(
        id: 1,
        startAt: start,
        endAt: end,
        status: BlockSession.statusActive,
        createdAt: start,
      );

      expect(session.isActive, isTrue);
      expect(session.isCompleted, isFalse);
      expect(session.isCancelled, isFalse);
      expect(session.isScheduled, isFalse);

      expect(session.isActiveAt(DateTime(2026, 10, 24, 10, 30)), isTrue);
      expect(session.isActiveAt(DateTime(2026, 10, 24, 9, 59)), isFalse);
      expect(session.isActiveAt(DateTime(2026, 10, 24, 11, 0)), isFalse);

      final remaining = session.remainingDuration(DateTime(2026, 10, 24, 10, 45));
      expect(remaining.inMinutes, equals(15));
      final pastRemaining = session.remainingDuration(DateTime(2026, 10, 24, 11, 30));
      expect(pastRemaining, equals(Duration.zero));

      final map = session.toMap();
      final fromMap = BlockSession.fromMap(map);
      expect(fromMap, equals(session));
      expect(fromMap.hashCode, equals(session.hashCode));
      expect(fromMap.toString(), contains('BlockSession'));

      final copy = session.copyWith(status: BlockSession.statusCompleted);
      expect(copy.isCompleted, isTrue);
    });
  });

  group('TemporaryUnlock Model Tests', () {
    test('status getters, isValidAt, remainingDuration, and serialization', () {
      final start = DateTime(2026, 10, 24, 10, 0);
      final end = DateTime(2026, 10, 24, 10, 15);
      final unlock = TemporaryUnlock(
        id: 1,
        appId: 10,
        sessionId: 20,
        startAt: start,
        endAt: end,
        status: TemporaryUnlock.statusActive,
        createdAt: start,
      );

      expect(unlock.isActive, isTrue);
      expect(unlock.isExpired, isFalse);
      expect(unlock.isRevoked, isFalse);

      expect(unlock.isValidAt(DateTime(2026, 10, 24, 10, 10)), isTrue);
      expect(unlock.isValidAt(DateTime(2026, 10, 24, 9, 59)), isFalse);
      expect(unlock.isValidAt(DateTime(2026, 10, 24, 10, 15)), isFalse);

      final remaining = unlock.remainingDuration(DateTime(2026, 10, 24, 10, 5));
      expect(remaining.inMinutes, equals(10));
      final pastRemaining = unlock.remainingDuration(DateTime(2026, 10, 24, 10, 20));
      expect(pastRemaining, equals(Duration.zero));

      final map = unlock.toMap();
      final fromMap = TemporaryUnlock.fromMap(map);
      expect(fromMap, equals(unlock));
      expect(fromMap.hashCode, equals(unlock.hashCode));
      expect(fromMap.toString(), contains('TemporaryUnlock'));

      final expired = unlock.copyWith(status: TemporaryUnlock.statusExpired);
      expect(expired.isExpired, isTrue);
    });
  });

  group('ActivityLog Model Tests', () {
    test('serialization, copyWith, and equality', () {
      final now = DateTime(2026, 10, 24, 10, 0);
      final log = ActivityLog(
        id: 1,
        appId: 5,
        sessionId: 10,
        packageNameSnapshot: 'com.example.app',
        appNameSnapshot: 'Example App',
        eventType: ActivityLog.eventBlockedAttempt,
        attemptedAt: now,
      );

      final map = log.toMap();
      final fromMap = ActivityLog.fromMap(map);
      expect(fromMap, equals(log));
      expect(fromMap.hashCode, equals(log.hashCode));
      expect(fromMap.toString(), contains('ActivityLog'));

      final copy = log.copyWith(eventType: ActivityLog.eventPasswordFailed);
      expect(copy.eventType, equals(ActivityLog.eventPasswordFailed));
      expect(copy, isNot(equals(log)));
    });

    test('supports outcome and details serialization and defaults to confirmed', () {
      final now = DateTime(2026, 10, 24, 10, 0);
      final log = ActivityLog(
        packageNameSnapshot: 'com.target.app',
        appNameSnapshot: 'Target App',
        eventType: ActivityLog.eventBlockedAttempt,
        outcome: ActivityLog.outcomeFailed,
        details: 'SecurityException: Not Allowed',
        attemptedAt: now,
      );

      final map = log.toMap();
      expect(map['outcome'], equals('failed'));
      expect(map['details'], equals('SecurityException: Not Allowed'));

      final fromMap = ActivityLog.fromMap(map);
      expect(fromMap.outcome, equals(ActivityLog.outcomeFailed));
      expect(fromMap.details, equals('SecurityException: Not Allowed'));

      final legacyMap = <String, dynamic>{
        'package_name_snapshot': 'com.legacy.app',
        'app_name_snapshot': 'Legacy App',
        'event_type': 'blocked_attempt',
        'attempted_at': now.millisecondsSinceEpoch,
      };
      final fromLegacy = ActivityLog.fromMap(legacyMap);
      expect(fromLegacy.outcome, equals(ActivityLog.outcomeConfirmed));
      expect(fromLegacy.details, isNull);
    });
  });

  group('AppSetting Model Tests', () {
    test('serialization, copyWith, and equality', () {
      final now = DateTime(2026, 10, 24, 10, 0);
      final setting = AppSetting(
        key: AppSetting.keyWaitingDurationSeconds,
        value: '300',
        updatedAt: now,
      );

      final map = setting.toMap();
      final fromMap = AppSetting.fromMap(map);
      expect(fromMap, equals(setting));
      expect(fromMap.hashCode, equals(setting.hashCode));
      expect(fromMap.toString(), contains('AppSetting'));

      final copy = setting.copyWith(value: '600');
      expect(copy.value, equals('600'));
      expect(copy, isNot(equals(setting)));
    });
  });
}
