class AppSetting {
  static const String keyWaitingDurationSeconds = 'waiting_duration_seconds';
  static const String keyPasswordHash = 'password_hash';
  static const String keyPasswordSalt = 'password_salt';
  static const String keyCustomLockMessage = 'custom_lock_message';
  static const String keyDefaultUnlockDurationSeconds = 'default_unlock_duration_seconds';

  static const int defaultWaitingDurationSeconds = 300;
  static const String defaultCustomLockMessage = 'Tetap fokus pada tujuanmu.';
  static const int defaultUnlockDurationSeconds = 600;

  final String key;
  final String value;
  final DateTime updatedAt;

  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'value': value,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory AppSetting.fromMap(Map<String, dynamic> map) {
    return AppSetting(
      key: map['key'] as String,
      value: map['value'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  AppSetting copyWith({
    String? key,
    String? value,
    DateTime? updatedAt,
  }) {
    return AppSetting(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSetting &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          value == other.value &&
          updatedAt.millisecondsSinceEpoch == other.updatedAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      key.hashCode ^ value.hashCode ^ updatedAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'AppSetting(key: $key, value: $value, updatedAt: $updatedAt)';
  }
}
