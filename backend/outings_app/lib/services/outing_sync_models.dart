// lib/services/outing_sync_models.dart
import 'dart:convert';

/// Payload to create a new outing offline, then sync online.
/// Keep fields minimal for your API; you can extend freely.
class OutingCreatePayload {
  final String tempId; // client-side temp id (before server assigns real id)
  final String title;
  final DateTime? startAt;
  final String? location;
  final String? notes;

  OutingCreatePayload({
    required this.tempId,
    required this.title,
    this.startAt,
    this.location,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'title': title,
        'startAt': startAt?.toIso8601String(),
        'location': location,
        'notes': notes,
      };

  static OutingCreatePayload fromJson(Map<String, dynamic> json) {
    return OutingCreatePayload(
      tempId: json['tempId'] as String,
      title: json['title'] as String,
      startAt:
          json['startAt'] != null ? DateTime.parse(json['startAt'] as String) : null,
      location: json['location'] as String?,
      notes: json['notes'] as String?,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Payload to update an existing outing offline, then sync online.
class OutingUpdatePayload {
  final String outingId; // server id
  final String? title;
  final DateTime? startAt;
  final String? location;
  final String? notes;

  OutingUpdatePayload({
    required this.outingId,
    this.title,
    this.startAt,
    this.location,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'outingId': outingId,
        'title': title,
        'startAt': startAt?.toIso8601String(),
        'location': location,
        'notes': notes,
      }..removeWhere((k, v) => v == null);

  static OutingUpdatePayload fromJson(Map<String, dynamic> json) {
    return OutingUpdatePayload(
      outingId: json['outingId'] as String,
      title: json['title'] as String?,
      startAt:
          json['startAt'] != null ? DateTime.parse(json['startAt'] as String) : null,
      location: json['location'] as String?,
      notes: json['notes'] as String?,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
