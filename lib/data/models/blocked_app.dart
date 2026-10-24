class BlockedApp {
  final int? id;
  final String packageName;
  final String appName;
  final bool isSelected;
  final DateTime createdAt;

  const BlockedApp({
    this.id,
    required this.packageName,
    required this.appName,
    this.isSelected = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'package_name': packageName,
      'app_name': appName,
      'is_selected': isSelected ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory BlockedApp.fromMap(Map<String, dynamic> map) {
    return BlockedApp(
      id: map['id'] as int?,
      packageName: map['package_name'] as String,
      appName: map['app_name'] as String,
      isSelected: (map['is_selected'] as int? ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  BlockedApp copyWith({
    int? id,
    String? packageName,
    String? appName,
    bool? isSelected,
    DateTime? createdAt,
  }) {
    return BlockedApp(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      isSelected: isSelected ?? this.isSelected,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockedApp &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          packageName == other.packageName &&
          appName == other.appName &&
          isSelected == other.isSelected &&
          createdAt.millisecondsSinceEpoch == other.createdAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      id.hashCode ^
      packageName.hashCode ^
      appName.hashCode ^
      isSelected.hashCode ^
      createdAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'BlockedApp(id: $id, packageName: $packageName, appName: $appName, isSelected: $isSelected, createdAt: $createdAt)';
  }
}
