// lib/models/discover_models.dart
import 'dart:convert';

class DiscoverResponse {
  final List<OutingModel> featured;
  final List<OutingModel> suggested;

  DiscoverResponse({
    required this.featured,
    required this.suggested,
  });

  factory DiscoverResponse.fromJson(Map<String, dynamic> json) {
    final f = (json['featured'] as List? ?? [])
        .map((e) => OutingModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final s = (json['suggested'] as List? ?? [])
        .map((e) => OutingModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return DiscoverResponse(featured: f, suggested: s);
  }

  static DiscoverResponse fromJsonString(String body) =>
      DiscoverResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
}

class OutingModel {
  final String id;
  final String title;
  final String? subtitle;
  final String type;
  final double lat;
  final double lng;
  final String? imageUrl;
  final double? distanceKm; // optional if backend returns distance

  OutingModel({
    required this.id,
    required this.title,
    required this.type,
    required this.lat,
    required this.lng,
    this.subtitle,
    this.imageUrl,
    this.distanceKm,
  });

  factory OutingModel.fromJson(Map<String, dynamic> json) {
    double _toD(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return OutingModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: json['subtitle']?.toString(),
      type: (json['type'] ?? 'Other').toString(),
      lat: _toD(json['lat'] ?? json['latitude']),
      lng: _toD(json['lng'] ?? json['longitude']),
      imageUrl: json['imageUrl']?.toString(),
      distanceKm: json['distanceKm'] != null ? _toD(json['distanceKm']) : null,
    );
  }
}

class DiscoverFilters {
  final List<String>? types; // e.g., ["Food","Hike"]
  final double? radiusKm;    // e.g., 10.0
  final int? limit;          // e.g., 20

  const DiscoverFilters({this.types, this.radiusKm, this.limit});

  Map<String, String> toQuery() {
    final q = <String, String>{};
    if (types != null && types!.isNotEmpty) {
      q['types'] = types!.join(',');
    }
    if (radiusKm != null) q['radiusKm'] = radiusKm!.toString();
    if (limit != null) q['limit'] = limit!.toString();
    return q;
  }
}
