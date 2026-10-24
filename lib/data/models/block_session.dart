class BlockSession {
  static const String statusScheduled = 'scheduled';
  static const String statusActive = 'active';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';

  final int? id;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final DateTime createdAt;

  const BlockSession({
    this.id,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.createdAt,
  });

  bool get isActive => status == statusActive;
  bool get isCompleted => status == statusCompleted;
  bool get isCancelled => status == statusCancelled;
  bool get isScheduled => status == statusScheduled;

  bool isActiveAt(DateTime dateTime) {
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

  factory BlockSession.fromMap(Map<String, dynamic> map) {
    return BlockSession(
      id: map['id'] as int?,
      startAt: DateTime.fromMillisecondsSinceEpoch(map['start_at'] as int),
      endAt: DateTime.fromMillisecondsSinceEpoch(map['end_at'] as int),
      status: map['status'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  BlockSession copyWith({
    int? id,
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    DateTime? createdAt,
  }) {
    return BlockSession(
      id: id ?? this.id,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockSession &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          startAt.millisecondsSinceEpoch == other.startAt.millisecondsSinceEpoch &&
          endAt.millisecondsSinceEpoch == other.endAt.millisecondsSinceEpoch &&
          status == other.status &&
          createdAt.millisecondsSinceEpoch == other.createdAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      id.hashCode ^
      startAt.millisecondsSinceEpoch.hashCode ^
      endAt.millisecondsSinceEpoch.hashCode ^
      status.hashCode ^
      createdAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'BlockSession(id: $id, startAt: $startAt, endAt: $endAt, status: $status)';
  }
}
