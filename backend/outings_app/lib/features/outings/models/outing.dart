// lib/features/outings/models/outing.dart
class Outing {
  final String id;
  final String title;
  final String? location;
  final DateTime? startsAt;
  final String? description;

  /// ✅ When created offline, we render as “syncing”
  final bool isLocalOnly;

  Outing({
    required this.id,
    required this.title,
    this.location,
    this.startsAt,
    this.description,
    this.isLocalOnly = false,
  });

  factory Outing.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['_id'] ?? '').toString();
    final parsedStartsAt = json['startsAt'] != null
        ? DateTime.tryParse(json['startsAt'].toString())
        : null;

    return Outing(
      id: id,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      location: json['location']?.toString(),
      startsAt: parsedStartsAt,
      description: json['description']?.toString(),
      // ✅ Prefer explicit field, otherwise infer from local id prefix
      isLocalOnly: (json['isLocalOnly'] as bool?) ?? id.startsWith('local-'),
    );
  }
}

class OutingDraft {
  final String title;
  final String? location;
  final DateTime? startsAt;
  final String? description;

  const OutingDraft({
    required this.title,
    this.location,
    this.startsAt,
    this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (location != null) 'location': location,
      if (startsAt != null) 'startsAt': startsAt!.toIso8601String(),
      if (description != null) 'description': description,
    };
  }
}
