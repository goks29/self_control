import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/block_rule.dart';

void main() {
  group('BlockRule Bitmask Tests', () {
    test('verifies individual day constants and masks', () {
      final rule = BlockRule.schedule(
        scheduleStartMinute: 540,
        scheduleEndMinute: 1020,
        daysMask: BlockRule.allDaysMask,
      );

      for (int day = 1; day <= 7; day++) {
        expect(rule.isDayEnabled(day), isTrue);
      }
      expect(rule.isDayEnabled(0), isFalse);
      expect(rule.isDayEnabled(8), isFalse);

      final weekdayRule = BlockRule.schedule(
        scheduleStartMinute: 540,
        scheduleEndMinute: 1020,
        daysMask: BlockRule.weekdaysMask,
      );
      expect(weekdayRule.isDayEnabled(DateTime.monday), isTrue);
      expect(weekdayRule.isDayEnabled(DateTime.tuesday), isTrue);
      expect(weekdayRule.isDayEnabled(DateTime.wednesday), isTrue);
      expect(weekdayRule.isDayEnabled(DateTime.thursday), isTrue);
      expect(weekdayRule.isDayEnabled(DateTime.friday), isTrue);
      expect(weekdayRule.isDayEnabled(DateTime.saturday), isFalse);
      expect(weekdayRule.isDayEnabled(DateTime.sunday), isFalse);

      final weekendRule = BlockRule.schedule(
        scheduleStartMinute: 540,
        scheduleEndMinute: 1020,
        daysMask: BlockRule.weekendMask,
      );
      expect(weekendRule.isDayEnabled(DateTime.saturday), isTrue);
      expect(weekendRule.isDayEnabled(DateTime.sunday), isTrue);
      expect(weekendRule.isDayEnabled(DateTime.monday), isFalse);
    });
  });

  group('BlockRule Daytime Schedule Tests', () {
    final rule = BlockRule.schedule(
      scheduleStartMinute: 540,
      scheduleEndMinute: 1020,
      daysMask: BlockRule.weekdaysMask,
    );

    test('is active within schedule window on active day', () {
      final wednesdayNoon = DateTime(2026, 10, 21, 12, 0);
      expect(wednesdayNoon.weekday, equals(DateTime.wednesday));
      expect(rule.isActiveAt(wednesdayNoon), isTrue);
    });

    test('is inactive before start minute', () {
      final wednesdayBefore = DateTime(2026, 10, 21, 8, 59);
      expect(rule.isActiveAt(wednesdayBefore), isFalse);
    });

    test('is active at exact start minute (inclusive)', () {
      final wednesdayStart = DateTime(2026, 10, 21, 9, 0);
      expect(rule.isActiveAt(wednesdayStart), isTrue);
    });

    test('is inactive at exact end minute (exclusive)', () {
      final wednesdayEnd = DateTime(2026, 10, 21, 17, 0);
      expect(rule.isActiveAt(wednesdayEnd), isFalse);
    });

    test('is inactive after end minute', () {
      final wednesdayAfter = DateTime(2026, 10, 21, 17, 30);
      expect(rule.isActiveAt(wednesdayAfter), isFalse);
    });

    test('is inactive on non-enabled day despite matching hours', () {
      final saturdayNoon = DateTime(2026, 10, 24, 12, 0);
      expect(saturdayNoon.weekday, equals(DateTime.saturday));
      expect(rule.isActiveAt(saturdayNoon), isFalse);
    });
  });

  group('BlockRule Overnight Schedule Tests', () {
    final mondayNightRule = BlockRule.schedule(
      scheduleStartMinute: 1320,
      scheduleEndMinute: 360,
      daysMask: BlockRule.dayMonday,
    );

    test('identifies as overnight rule', () {
      expect(mondayNightRule.isOvernight, isTrue);
    });

    test('is active at evening start minute on enabled day', () {
      final mondayStart = DateTime(2026, 10, 19, 22, 0);
      expect(mondayStart.weekday, equals(DateTime.monday));
      expect(mondayNightRule.isActiveAt(mondayStart), isTrue);
    });

    test('is active pre-midnight on enabled day', () {
      final mondayLate = DateTime(2026, 10, 19, 23, 59);
      expect(mondayNightRule.isActiveAt(mondayLate), isTrue);
    });

    test('is active at midnight rollover from enabled previous day', () {
      final tuesdayMidnight = DateTime(2026, 10, 20, 0, 0);
      expect(tuesdayMidnight.weekday, equals(DateTime.tuesday));
      expect(mondayNightRule.isActiveAt(tuesdayMidnight), isTrue);
    });

    test('is active early morning from enabled previous day', () {
      final tuesdayEarly = DateTime(2026, 10, 20, 3, 30);
      expect(mondayNightRule.isActiveAt(tuesdayEarly), isTrue);
    });

    test('is inactive at morning end minute (exclusive)', () {
      final tuesdayEnd = DateTime(2026, 10, 20, 6, 0);
      expect(mondayNightRule.isActiveAt(tuesdayEnd), isFalse);
    });

    test('is inactive during daytime gap', () {
      final tuesdayMidday = DateTime(2026, 10, 20, 14, 0);
      expect(mondayNightRule.isActiveAt(tuesdayMidday), isFalse);
    });

    test('is inactive on Tuesday night when Tuesday not in mask', () {
      final tuesdayNight = DateTime(2026, 10, 20, 22, 30);
      expect(mondayNightRule.isActiveAt(tuesdayNight), isFalse);
    });

    test('is inactive on Wednesday morning when Tuesday not in mask', () {
      final wednesdayMorning = DateTime(2026, 10, 21, 2, 0);
      expect(mondayNightRule.isActiveAt(wednesdayMorning), isFalse);
    });

    test('handles Sunday evening to Monday morning rollover', () {
      final sundayNightRule = BlockRule.schedule(
        scheduleStartMinute: 1320,
        scheduleEndMinute: 360,
        daysMask: BlockRule.daySunday,
      );

      final sundayEvening = DateTime(2026, 10, 25, 23, 0);
      expect(sundayEvening.weekday, equals(DateTime.sunday));
      expect(sundayNightRule.isActiveAt(sundayEvening), isTrue);

      final mondayMorning = DateTime(2026, 10, 26, 3, 0);
      expect(mondayMorning.weekday, equals(DateTime.monday));
      expect(sundayNightRule.isActiveAt(mondayMorning), isTrue);

      final mondayNight = DateTime(2026, 10, 26, 23, 0);
      expect(sundayNightRule.isActiveAt(mondayNight), isFalse);
    });

    test('handles consecutive overnight days (Fri + Sat)', () {
      final weekendNightsRule = BlockRule.schedule(
        scheduleStartMinute: 1380,
        scheduleEndMinute: 420,
        daysMask: BlockRule.dayFriday | BlockRule.daySaturday,
      );

      final saturdayMorning = DateTime(2026, 10, 24, 4, 0);
      expect(saturdayMorning.weekday, equals(DateTime.saturday));
      expect(weekendNightsRule.isActiveAt(saturdayMorning), isTrue);

      final sundayMorning = DateTime(2026, 10, 25, 4, 0);
      expect(sundayMorning.weekday, equals(DateTime.sunday));
      expect(weekendNightsRule.isActiveAt(sundayMorning), isTrue);

      final mondayMorning = DateTime(2026, 10, 26, 4, 0);
      expect(mondayMorning.weekday, equals(DateTime.monday));
      expect(weekendNightsRule.isActiveAt(mondayMorning), isFalse);
    });
  });

  group('BlockRule State and Mode Invariant Tests', () {
    test('returns false when rule is disabled', () {
      final disabledRule = BlockRule.schedule(
        scheduleStartMinute: 540,
        scheduleEndMinute: 1020,
        daysMask: BlockRule.allDaysMask,
        isEnabled: false,
      );

      final wednesdayNoon = DateTime(2026, 10, 21, 12, 0);
      expect(disabledRule.isActiveAt(wednesdayNoon), isFalse);
    });

    test('returns false for duration mode rules in isActiveAt', () {
      final durationRule = BlockRule.duration(durationMinutes: 60);
      final now = DateTime(2026, 10, 21, 12, 0);
      expect(durationRule.isDurationMode, isTrue);
      expect(durationRule.isActiveAt(now), isFalse);
    });

    test('serializes and deserializes correctly', () {
      final original = BlockRule.schedule(
        id: 42,
        scheduleStartMinute: 1320,
        scheduleEndMinute: 420,
        daysMask: 31,
        isEnabled: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      final map = original.toMap();
      final reconstituted = BlockRule.fromMap(map);

      expect(reconstituted, equals(original));
      expect(reconstituted.hashCode, equals(original.hashCode));

      final updated = original.copyWith(scheduleEndMinute: 480);
      expect(updated.scheduleEndMinute, equals(480));
      expect(updated.scheduleStartMinute, equals(1320));
      expect(updated, isNot(equals(original)));
    });
  });
}
