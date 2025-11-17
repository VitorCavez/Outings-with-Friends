// lib/services/places_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class PlaceSuggestion {
  final String source; // 'saved' | 'osm'
  final String id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;

  PlaceSuggestion({
    required this.source,
    required this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> j) => PlaceSuggestion(
    source: (j['source'] ?? 'osm').toString(),
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    address: j['address'] as String?,
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
  );
}

class PlacesService {
  static Future<List<PlaceSuggestion>> search(String q, {String? token}) async {
    if (q.trim().isEmpty) return [];
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/geo/search?q=${Uri.encodeQueryComponent(q)}',
    );
    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = jsonDecode(res.body);
      final list = (decoded is Map && decoded['data'] is List)
          ? decoded['data'] as List
          : const [];
      return list
          .map((e) => PlaceSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static Future<PlaceSuggestion?> saveCustom({
    required String name,
    String? address,
    required double latitude,
    required double longitude,
    required String token,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/places');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        if (address != null && address.trim().isNotEmpty)
          'address': address.trim(),
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final decoded = jsonDecode(res.body);
      final j = (decoded['data'] as Map<String, dynamic>);
      return PlaceSuggestion(
        source: 'saved',
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        address: j['address'] as String?,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
      );
    }
    return null;
  }
}
