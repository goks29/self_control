class FocusTask {
  final int? id;
  final String title;
  final bool isCompleted;
  final DateTime createdAt;

  const FocusTask({
    this.id,
    required this.title,
    this.isCompleted = false,
    required this.createdAt,
  });

  FocusTask copyWith({
    int? id,
    String? title,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return FocusTask(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory FocusTask.fromMap(Map<String, dynamic> map) {
    return FocusTask(
      id: map['id'] as int?,
      title: (map['title'] as String?) ?? '',
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
