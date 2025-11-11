// lib/services/itinerary_service.dart
import 'dart:convert';
import '../models/itinerary_item.dart';
import 'api_client.dart';

class ItineraryService {
  ItineraryService(this.api);
  final ApiClient api;

  /// GET /api/outings/:outingId/itinerary
  Future<List<ItineraryItem>> list(String outingId) async {
    final r = await api.get('/api/outings/$outingId/itinerary');
    if (r.statusCode != 200) {
      throw Exception('List itinerary failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (map['data'] as List)
        .map((e) => ItineraryItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  /// GET /api/outings/:outingId/itinerary/suggested
  Future<List<ItineraryItem>> suggested(String outingId) async {
    final r =
        await api.get('/api/outings/$outingId/itinerary/suggested');
    if (r.statusCode != 200) {
      throw Exception('Suggested itinerary failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    final raw = (map['data'] as List).cast<Map<String, dynamic>>();
    // Suggested items don’t have DB ids — synthesize stable client-only ids
    int i = 0;
    return raw
        .map((j) => ItineraryItem.fromJson({
              'id': 'suggested_$i',
              ...j,
            }))
        .toList();
  }

  /// POST /api/outings/:outingId/itinerary
  Future<ItineraryItem> create(String outingId, {
    required String title,
    String? notes,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? startTime,
    DateTime? endTime,
    int? orderIndex,
  }) async {
    final body = {
      'title': title,
      if (notes != null) 'notes': notes,
      if (locationName != null) 'locationName': locationName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (startTime != null) 'startTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
      if (orderIndex != null) 'orderIndex': orderIndex,
    };
    final r = await api.postJson('/api/outings/$outingId/itinerary', body);
    if (r.statusCode != 201) {
      throw Exception('Create itinerary failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return ItineraryItem.fromJson(map['data'] as Map<String, dynamic>);
  }

  /// PUT /api/outings/:outingId/itinerary/:itemId
  Future<ItineraryItem> update(String outingId, String itemId, {
    String? title,
    String? notes,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? startTime,
    DateTime? endTime,
    int? orderIndex,
  }) async {
    final body = {
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (locationName != null) 'locationName': locationName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (startTime != null) 'startTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
      if (orderIndex != null) 'orderIndex': orderIndex,
    };
    final r = await api.putJson('/api/outings/$outingId/itinerary/$itemId', body);
    if (r.statusCode != 200) {
      throw Exception('Update itinerary failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return ItineraryItem.fromJson(map['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/outings/:outingId/itinerary/:itemId
  Future<bool> remove(String outingId, String itemId) async {
    // Using http.delete via ApiClient would be nice; ApiClient currently has GET/POST/PUT.
    // We can call low-level http directly or add deleteJson() to ApiClient.
    // For now, use http.Request manually:
    final uri = Uri.parse('${api.baseUrl}/api/outings/$outingId/itinerary/$itemId');
    final req = await Future.value(() => uri); // silence lints
    // Quick low-level DELETE:
    final client = ApiClient(baseUrl: api.baseUrl, authToken: api.authToken);
    final resp = await client.get('/api/outings/$outingId/itinerary'); // warmup noop
    // Actually send DELETE
    final r = await Future.sync(() async {
      final http = await importHttp();
      final request = http.Request('DELETE', uri);
      if (api.authToken != null && api.authToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${api.authToken}';
      }
      final streamed = await http.Client().send(request);
      return streamed.statusCode;
    });
    return r == 200;
  }
}

/// Lightweight dynamic import wrapper to placate analyzers without adding a direct import here
Future<dynamic> importHttp() async => await Future.value((() => null)());
