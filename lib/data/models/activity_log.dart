class ActivityLog {
  static const String eventBlockedAttempt = 'blocked_attempt';
  static const String eventPasswordFailed = 'password_failed';
  static const String eventTemporaryUnlockStarted = 'temporary_unlock_started';
  static const String eventTemporaryUnlockExpired = 'temporary_unlock_expired';
  static const String eventBlockStarted = 'block_started';
  static const String eventBlockEnded = 'block_ended';

  final int? id;
  final int? appId;
  final int? sessionId;
  final String packageNameSnapshot;
  final String appNameSnapshot;
  final String eventType;
  final DateTime attemptedAt;

  const ActivityLog({
    this.id,
    this.appId,
    this.sessionId,
    required this.packageNameSnapshot,
    required this.appNameSnapshot,
    required this.eventType,
    required this.attemptedAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'app_id': appId,
      'session_id': sessionId,
      'package_name_snapshot': packageNameSnapshot,
      'app_name_snapshot': appNameSnapshot,
      'event_type': eventType,
      'attempted_at': attemptedAt.millisecondsSinceEpoch,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory ActivityLog.fromMap(Map<String, dynamic> map) {
    return ActivityLog(
      id: map['id'] as int?,
      appId: map['app_id'] as int?,
      sessionId: map['session_id'] as int?,
      packageNameSnapshot: map['package_name_snapshot'] as String,
      appNameSnapshot: map['app_name_snapshot'] as String,
      eventType: map['event_type'] as String,
      attemptedAt: DateTime.fromMillisecondsSinceEpoch(map['attempted_at'] as int),
    );
  }

  ActivityLog copyWith({
    int? id,
    int? appId,
    int? sessionId,
    String? packageNameSnapshot,
    String? appNameSnapshot,
    String? eventType,
    DateTime? attemptedAt,
  }) {
    return ActivityLog(
      id: id ?? this.id,
      appId: appId ?? this.appId,
      sessionId: sessionId ?? this.sessionId,
      packageNameSnapshot: packageNameSnapshot ?? this.packageNameSnapshot,
      appNameSnapshot: appNameSnapshot ?? this.appNameSnapshot,
      eventType: eventType ?? this.eventType,
      attemptedAt: attemptedAt ?? this.attemptedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityLog &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          appId == other.appId &&
          sessionId == other.sessionId &&
          packageNameSnapshot == other.packageNameSnapshot &&
          appNameSnapshot == other.appNameSnapshot &&
          eventType == other.eventType &&
          attemptedAt.millisecondsSinceEpoch == other.attemptedAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      id.hashCode ^
      appId.hashCode ^
      sessionId.hashCode ^
      packageNameSnapshot.hashCode ^
      appNameSnapshot.hashCode ^
      eventType.hashCode ^
      attemptedAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'ActivityLog(id: $id, pkg: $packageNameSnapshot, app: $appNameSnapshot, event: $eventType, at: $attemptedAt)';
  }
}
