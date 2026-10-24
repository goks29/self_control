class TemporaryUnlock {
  static const String statusActive = 'active';
  static const String statusExpired = 'expired';
  static const String statusRevoked = 'revoked';

  final int? id;
  final int appId;
  final int? sessionId;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final DateTime createdAt;

  const TemporaryUnlock({
    this.id,
    required this.appId,
    this.sessionId,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.createdAt,
  });

  bool get isActive => status == statusActive;
  bool get isExpired => status == statusExpired;
  bool get isRevoked => status == statusRevoked;

  bool isValidAt(DateTime dateTime) {
    if (status != statusActive) return false;
    final epoch = dateTime.millisecondsSinceEpoch;
    return epoch >= startAt.millisecondsSinceEpoch && epoch < endAt.millisecondsSinceEpoch;
  }

  Duration remainingDuration(DateTime dateTime) {
    final diff = endAt.difference(dateTime);
    return diff.isNegative ? Duration.zero : diff;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'app_id': appId,
      'session_id': sessionId,
      'start_at': startAt.millisecondsSinceEpoch,
      'end_at': endAt.millisecondsSinceEpoch,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory TemporaryUnlock.fromMap(Map<String, dynamic> map) {
    return TemporaryUnlock(
      id: map['id'] as int?,
      appId: map['app_id'] as int,
      sessionId: map['session_id'] as int?,
      startAt: DateTime.fromMillisecondsSinceEpoch(map['start_at'] as int),
      endAt: DateTime.fromMillisecondsSinceEpoch(map['end_at'] as int),
      status: map['status'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  TemporaryUnlock copyWith({
    int? id,
    int? appId,
    int? sessionId,
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    DateTime? createdAt,
  }) {
    return TemporaryUnlock(
      id: id ?? this.id,
      appId: appId ?? this.appId,
      sessionId: sessionId ?? this.sessionId,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemporaryUnlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          appId == other.appId &&
          sessionId == other.sessionId &&
          startAt.millisecondsSinceEpoch == other.startAt.millisecondsSinceEpoch &&
          endAt.millisecondsSinceEpoch == other.endAt.millisecondsSinceEpoch &&
          status == other.status &&
          createdAt.millisecondsSinceEpoch == other.createdAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      id.hashCode ^
      appId.hashCode ^
      sessionId.hashCode ^
      startAt.millisecondsSinceEpoch.hashCode ^
      endAt.millisecondsSinceEpoch.hashCode ^
      status.hashCode ^
      createdAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'TemporaryUnlock(id: $id, appId: $appId, sessionId: $sessionId, startAt: $startAt, endAt: $endAt, status: $status)';
  }
}
