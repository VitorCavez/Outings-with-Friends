// lib/services/discover_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/discover_models.dart';

class DiscoverService {
  final http.Client _client;

  DiscoverService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the discover feed from your backend:
  /// GET /discover?lat=..&lng=..&radiusKm=..&types=Food,Hike&limit=20
  ///
  /// Expected JSON shape:
  /// {
  ///   "featured": [ { id, title, subtitle?, type, lat, lng, imageUrl? } ],
  ///   "suggested": [ { ... same fields ... } ]
  /// }
  Future<DiscoverResponse> fetchDiscover({
    required double lat,
    required double lng,
    DiscoverFilters filters = const DiscoverFilters(),
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final base = AppConfig.apiBaseUrl;
    final uri = Uri.parse('$base/discover').replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      ...filters.toQuery(),
    });

    final res = await _client
        .get(uri, headers: {'Content-Type': 'application/json'})
        .timeout(timeout);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // accept either object or string body
      if (res.body.isEmpty) {
        return DiscoverResponse(featured: const [], suggested: const []);
      }
      final body = res.body;
      // try: if body unwraps directly
      try {
        return DiscoverResponse.fromJson(
            jsonDecode(body) as Map<String, dynamic>);
      } catch (_) {
        // fallback: model helper
        return DiscoverResponse.fromJsonString(body);
      }
    }

    // Map some common server errors to readable messages
    String msg = 'Failed to load discover (${res.statusCode}).';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['message'] is String) {
        msg = decoded['message'];
      }
    } catch (_) {}

    throw HttpException(msg);
  }
}
