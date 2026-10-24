class ActivityLog {
  static const String eventBlockedAttempt = 'blocked_attempt';
  static const String eventPasswordFailed = 'password_failed';
  static const String eventTemporaryUnlockStarted = 'temporary_unlock_started';
  static const String eventTemporaryUnlockExpired = 'temporary_unlock_expired';
  static const String eventBlockStarted = 'block_started';
  static const String eventBlockEnded = 'block_ended';
  static const String eventTamperingDetected = 'tampering_detected';
  static const String eventBootCompletedSync = 'boot_completed_sync';
  static const String eventFailsafeRecovery = 'failsafe_recovery';

  static const String outcomeNotRequired = 'not_required';
  static const String outcomeAttempted = 'attempted';
  static const String outcomeConfirmed = 'confirmed';
  static const String outcomeFailed = 'failed';
  static const String outcomeUnknown = 'unknown';

  final int? id;
  final int? appId;
  final int? sessionId;
  final String packageNameSnapshot;
  final String appNameSnapshot;
  final String eventType;
  final String outcome;
  final String? details;
  final DateTime attemptedAt;

  const ActivityLog({
    this.id,
    this.appId,
    this.sessionId,
    required this.packageNameSnapshot,
    required this.appNameSnapshot,
    required this.eventType,
    this.outcome = outcomeConfirmed,
    this.details,
    required this.attemptedAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'app_id': appId,
      'session_id': sessionId,
      'package_name_snapshot': packageNameSnapshot,
      'app_name_snapshot': appNameSnapshot,
      'event_type': eventType,
      'outcome': outcome,
      'details': details,
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
      outcome: (map['outcome'] as String?) ?? outcomeConfirmed,
      details: map['details'] as String?,
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
    String? outcome,
    String? details,
    DateTime? attemptedAt,
  }) {
    return ActivityLog(
      id: id ?? this.id,
      appId: appId ?? this.appId,
      sessionId: sessionId ?? this.sessionId,
      packageNameSnapshot: packageNameSnapshot ?? this.packageNameSnapshot,
      appNameSnapshot: appNameSnapshot ?? this.appNameSnapshot,
      eventType: eventType ?? this.eventType,
      outcome: outcome ?? this.outcome,
      details: details ?? this.details,
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
          outcome == other.outcome &&
          details == other.details &&
          attemptedAt.millisecondsSinceEpoch == other.attemptedAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      id.hashCode ^
      appId.hashCode ^
      sessionId.hashCode ^
      packageNameSnapshot.hashCode ^
      appNameSnapshot.hashCode ^
      eventType.hashCode ^
      outcome.hashCode ^
      details.hashCode ^
      attemptedAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'ActivityLog(id: $id, pkg: $packageNameSnapshot, app: $appNameSnapshot, event: $eventType, outcome: $outcome, details: $details, at: $attemptedAt)';
  }
}
