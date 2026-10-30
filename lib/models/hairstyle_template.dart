class HairstyleTemplate {
  final int? id;
  final String name;
  final DateTime createdAt;

  HairstyleTemplate({this.id, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Model adı boş olamaz.');
    }
  }

  String get appointmentHairstyleId => 'custom:$id';

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name.trim(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory HairstyleTemplate.fromMap(Map<String, dynamic> map) =>
      HairstyleTemplate(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
