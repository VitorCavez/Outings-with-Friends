// lib/models/group_models.dart
class Group {
  final String id;
  final String name;
  final String? description;
  final String createdById;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    required this.createdById,
    required this.createdAt,
    this.description,
  });

  factory Group.fromJson(Map<String, dynamic> j) => Group(
    id: j['id'] as String,
    name: j['name'] as String,
    createdById: j['createdById'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    description: j['description'] as String?,
  );
}
