class BlockRule {
  static const String modeDuration = 'duration';
  static const String modeSchedule = 'schedule';

  static const int dayMonday = 1;
  static const int dayTuesday = 2;
  static const int dayWednesday = 4;
  static const int dayThursday = 8;
  static const int dayFriday = 16;
  static const int daySaturday = 32;
  static const int daySunday = 64;
  static const int allDaysMask = 127;
  static const int weekdaysMask = 31;
  static const int weekendMask = 96;

  final int? id;
  final String mode;
  final int? durationMinutes;
  final int? scheduleStartMinute;
  final int? scheduleEndMinute;
  final int? daysMask;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BlockRule({
    this.id,
    required this.mode,
    this.durationMinutes,
    this.scheduleStartMinute,
    this.scheduleEndMinute,
    this.daysMask,
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BlockRule.duration({
    int? id,
    required int durationMinutes,
    bool isEnabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return BlockRule(
      id: id,
      mode: modeDuration,
      durationMinutes: durationMinutes,
      isEnabled: isEnabled,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  factory BlockRule.schedule({
    int? id,
    required int scheduleStartMinute,
    required int scheduleEndMinute,
    required int daysMask,
    bool isEnabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return BlockRule(
      id: id,
      mode: modeSchedule,
      scheduleStartMinute: scheduleStartMinute,
      scheduleEndMinute: scheduleEndMinute,
      daysMask: daysMask,
      isEnabled: isEnabled,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  bool get isDurationMode => mode == modeDuration;
  bool get isScheduleMode => mode == modeSchedule;
  bool get isOvernight =>
      isScheduleMode &&
      scheduleStartMinute != null &&
      scheduleEndMinute != null &&
      scheduleStartMinute! > scheduleEndMinute!;

  bool isDayEnabled(int weekday) {
    if (daysMask == null || weekday < 1 || weekday > 7) return false;
    return (daysMask! & (1 << (weekday - 1))) != 0;
  }

  bool isActiveAt(DateTime dateTime) {
    if (!isEnabled) return false;
    if (mode != modeSchedule) return false;
    if (scheduleStartMinute == null || scheduleEndMinute == null || daysMask == null) {
      return false;
    }

    final start = scheduleStartMinute!;
    final end = scheduleEndMinute!;
    final mask = daysMask!;

    final currentMinute = dateTime.hour * 60 + dateTime.minute;
    final currentWeekday = dateTime.weekday;

    if (start < end) {
      final isTodayEnabled = (mask & (1 << (currentWeekday - 1))) != 0;
      return isTodayEnabled && (currentMinute >= start && currentMinute < end);
    } else if (start > end) {
      if (currentMinute >= start) {
        final isTodayEnabled = (mask & (1 << (currentWeekday - 1))) != 0;
        return isTodayEnabled;
      }

      if (currentMinute < end) {
        final previousWeekday = (currentWeekday == 1) ? 7 : currentWeekday - 1;
        final wasYesterdayEnabled = (mask & (1 << (previousWeekday - 1))) != 0;
        return wasYesterdayEnabled;
      }

      return false;
    }

    return false;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'mode': mode,
      'duration_minutes': durationMinutes,
      'schedule_start_minute': scheduleStartMinute,
      'schedule_end_minute': scheduleEndMinute,
      'days_mask': daysMask,
      'is_enabled': isEnabled ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory BlockRule.fromMap(Map<String, dynamic> map) {
    return BlockRule(
      id: map['id'] as int?,
      mode: map['mode'] as String,
      durationMinutes: map['duration_minutes'] as int?,
      scheduleStartMinute: map['schedule_start_minute'] as int?,
      scheduleEndMinute: map['schedule_end_minute'] as int?,
      daysMask: map['days_mask'] as int?,
      isEnabled: (map['is_enabled'] as int? ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  BlockRule copyWith({
    int? id,
    String? mode,
    int? durationMinutes,
    int? scheduleStartMinute,
    int? scheduleEndMinute,
    int? daysMask,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BlockRule(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      scheduleStartMinute: scheduleStartMinute ?? this.scheduleStartMinute,
      scheduleEndMinute: scheduleEndMinute ?? this.scheduleEndMinute,
      daysMask: daysMask ?? this.daysMask,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockRule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mode == other.mode &&
          durationMinutes == other.durationMinutes &&
          scheduleStartMinute == other.scheduleStartMinute &&
          scheduleEndMinute == other.scheduleEndMinute &&
          daysMask == other.daysMask &&
          isEnabled == other.isEnabled &&
          createdAt.millisecondsSinceEpoch == other.createdAt.millisecondsSinceEpoch &&
          updatedAt.millisecondsSinceEpoch == other.updatedAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      id.hashCode ^
      mode.hashCode ^
      durationMinutes.hashCode ^
      scheduleStartMinute.hashCode ^
      scheduleEndMinute.hashCode ^
      daysMask.hashCode ^
      isEnabled.hashCode ^
      createdAt.millisecondsSinceEpoch.hashCode ^
      updatedAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'BlockRule(id: $id, mode: $mode, duration: $durationMinutes, schedule: $scheduleStartMinute-$scheduleEndMinute, daysMask: $daysMask, isEnabled: $isEnabled)';
  }
}
