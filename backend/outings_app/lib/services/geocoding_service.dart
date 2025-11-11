import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Simple data model for coordinates.
class Coordinates {
  final double lat;
  final double lng;

  const Coordinates({required this.lat, required this.lng});
}

/// A single place result from OpenCage.
class PlaceResult {
  final String formatted;               // e.g., "Dublin, Ireland"
  final Coordinates coordinates;        // lat/lng
  final Map<String, dynamic> components; // raw components (city, road, country, etc.)
  final double? confidence;             // 1..10 (OpenCage heuristic)

  PlaceResult({
    required this.formatted,
    required this.coordinates,
    required this.components,
    this.confidence,
  });
}

/// Wrapper for a geocoding response (can hold multiple places).
class GeocodingResponse {
  final List<PlaceResult> results;
  final int total;
  final bool isRateLimited;
  final String? error;

  GeocodingResponse({
    required this.results,
    required this.total,
    required this.isRateLimited,
    this.error,
  });

  bool get ok => error == null && results.isNotEmpty;
}

/// Service for forward (address -> lat/lng) and reverse (lat/lng -> address) geocoding.
class GeocodingService {
  static const _baseUrl = "https://api.opencagedata.com/geocode/v1/json";
  static const _placeholderKey = 'YOUR_OPENCAGE_KEY_HERE';

  /// Forward geocoding: text address -> coordinates and places.
  ///
  /// [address] The human-readable query, e.g. "Temple Bar, Dublin".
  /// [limit]   Max number of results (1..10).
  /// [language] Optional BCP-47 code, e.g. "en", "pt", "es".
  /// [countrycode] Optional ISO 3166-1 alpha-2 filter, e.g. "ie" for Ireland.
  Future<GeocodingResponse> forward({
    required String address,
    int limit = 5,
    String? language,
    String? countrycode,
  }) async {
    final key = AppConfig.openCageApiKey;
    if (key.isEmpty || key == _placeholderKey) {
      return GeocodingResponse(
        results: const [],
        total: 0,
        isRateLimited: false,
        error:
            "OpenCage API key is missing. Pass it with --dart-define=OPENCAGE_API_KEY=...",
      );
    }

    final params = <String, String>{
      "q": address,
      "key": key,
      "limit": limit.clamp(1, 10).toString(),
      "no_annotations": "1", // lighter response
    };
    if (language != null && language.isNotEmpty) params["language"] = language;
    if (countrycode != null && countrycode.isNotEmpty) {
      params["countrycode"] = countrycode;
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    return _send(uri);
  }

  /// Reverse geocoding: coordinates -> nearest address/place.
  ///
  /// [coords]  Lat/Lng pair.
  /// [limit]   Max number of results (1..10).
  /// [language] Optional BCP-47 code, e.g. "en".
  Future<GeocodingResponse> reverse({
    required Coordinates coords,
    int limit = 1,
    String? language,
  }) async {
    final key = AppConfig.openCageApiKey;
    if (key.isEmpty || key == _placeholderKey) {
      return GeocodingResponse(
        results: const [],
        total: 0,
        isRateLimited: false,
        error:
            "OpenCage API key is missing. Pass it with --dart-define=OPENCAGE_API_KEY=...",
      );
    }

    final q = "${coords.lat}+${coords.lng}";
    final params = <String, String>{
      "q": q,
      "key": key,
      "limit": limit.clamp(1, 10).toString(),
      "no_annotations": "1",
    };
    if (language != null && language.isNotEmpty) params["language"] = language;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    return _send(uri);
  }

  /// Shared HTTP call + parsing.
  Future<GeocodingResponse> _send(Uri uri) async {
    try {
      final res = await http
          .get(
            uri,
            headers: {
              HttpHeaders.acceptHeader: "application/json",
              HttpHeaders.userAgentHeader: "outings-app/1.0",
            },
          )
          .timeout(const Duration(seconds: 15));

      // Basic network errors
      if (res.statusCode == 429) {
        return GeocodingResponse(
          results: const [],
          total: 0,
          isRateLimited: true,
          error: "Rate limit reached (HTTP 429) from OpenCage.",
        );
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return GeocodingResponse(
          results: const [],
          total: 0,
          isRateLimited: false,
          error: "OpenCage error: HTTP ${res.statusCode}",
        );
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final rate = (data["rate"] as Map?) ?? {};
      final remaining = rate["remaining"];
      final isLimited = (remaining is num) ? remaining <= 0 : false;

      final results = (data["results"] as List? ?? [])
          .map((r) => _parsePlace(r as Map<String, dynamic>))
          .whereType<PlaceResult>()
          .toList();

      final total = (data["total_results"] is int)
          ? data["total_results"] as int
          : results.length;

      return GeocodingResponse(
        results: results,
        total: total,
        isRateLimited: isLimited,
        error: null,
      );
    } on SocketException {
      return GeocodingResponse(
        results: const [],
        total: 0,
        isRateLimited: false,
        error: "No internet connection.",
      );
    } on FormatException {
      return GeocodingResponse(
        results: const [],
        total: 0,
        isRateLimited: false,
        error: "Invalid JSON from OpenCage.",
      );
    } on HttpException catch (e) {
      return GeocodingResponse(
        results: const [],
        total: 0,
        isRateLimited: false,
        error: "HTTP error: ${e.message}",
      );
    } on Exception catch (e) {
      return GeocodingResponse(
        results: const [],
        total: 0,
        isRateLimited: false,
        error: "Unexpected error: $e",
      );
    }
  }

  PlaceResult? _parsePlace(Map<String, dynamic> r) {
    try {
      final formatted = (r["formatted"] as String?) ?? "";
      final geometry = r["geometry"] as Map<String, dynamic>?;
      final components =
          (r["components"] as Map?)?.cast<String, dynamic>() ?? {};
      final confidence = (r["confidence"] is num)
          ? (r["confidence"] as num).toDouble()
          : null;

      if (geometry == null) return null;

      final lat = (geometry["lat"] as num).toDouble();
      final lng = (geometry["lng"] as num).toDouble();

      return PlaceResult(
        formatted: formatted,
        coordinates: Coordinates(lat: lat, lng: lng),
        components: components,
        confidence: confidence,
      );
    } catch (_) {
      return null;
    }
  }
}
