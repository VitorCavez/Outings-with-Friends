// lib/features/outings/outings_repository.dart
import 'dart:convert';
import 'dart:io'; // 👈 for SocketException
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../services/api_client.dart';
import '../../services/outbox_service.dart';
import 'models/outing.dart';

class OutingsRepository {
  OutingsRepository(this._api);
  final ApiClient _api;

  // ---- Helpers -------------------------------------------------------------

  List<dynamic> _extractList(dynamic data) {
    // Accept: [ ... ]
    if (data is List) return data;

    // Accept: { data: [...] } or { outings: [...] } or { items: [...] } or { results: [...] }
    if (data is Map) {
      for (final key in const ['data', 'outings', 'items', 'results', 'list']) {
        final v = data[key];
        if (v is List) return v;
      }
      // Accept nested: { data: { items: [...] } } etc.
      final d = data['data'];
      if (d is Map) {
        for (final key in const ['items', 'outings', 'results', 'list']) {
          final v = d[key];
          if (v is List) return v;
        }
      }
    }
    return const [];
  }

  Map<String, dynamic> _extractObject(dynamic data) {
    // Accept: { ... }
    if (data is Map<String, dynamic>) return data;

    // Accept: { outing: {...} } or { data: {...} }
    if (data is Map) {
      for (final key in const ['outing', 'data', 'result', 'item']) {
        final v = data[key];
        if (v is Map<String, dynamic>) return v;
      }
    }

    // As a last resort, try to coerce
    return (data as Map).cast<String, dynamic>();
  }

  // ---- API calls -----------------------------------------------------------

  /// Fetch all outings.
  /// Accepts JSON like:
  ///  - [ ... ]
  ///  - { data: [...] }
  ///  - { outings: [...] }
  ///  - { data: { items: [...] } }
  Future<List<Outing>> fetchOutings() async {
    // Use ApiClient for consistent base URL + headers
    final res = await _api.get('/api/outings');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body);
      final list = _extractList(data);
      return list
          .where((e) => e is Map)
          .map((e) => Outing.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }
    throw Exception('GET /api/outings -> ${res.statusCode}: ${res.body}');
  }

  /// Fetch a single outing by id.
  /// Accepts JSON like:
  ///  - { outing: {...} }
  ///  - { data: {...} }
  ///  - { ... } (direct object)
  /// Returns `null` for 404s or on offline errors.
  Future<Outing?> fetchOutingById(String id) async {
    try {
      final res = await _api.get('/api/outings/$id');
      if (res.statusCode == 404) return null;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final map = _extractObject(data);
        return Outing.fromJson(map);
      }
      throw Exception('GET /api/outings/$id -> ${res.statusCode}: ${res.body}');
    } on SocketException {
      // Offline — let caller decide how to show cached/placeholder data.
      return null;
    }
  }

  /// Creates an outing online when possible. If offline, we enqueue an
  /// Outbox "outingCreate" task and return a local placeholder model
  /// (id: 'local-<clientId>') so UI can render immediately.
  Future<Outing> createOuting(OutingDraft draft) async {
    try {
      final res = await _api.postJson('/api/outings', draft.toJson());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        // Accept: { outing: {...} }, { data: {...} } or direct object
        Map<String, dynamic> map;
        if (data is Map && data['outing'] is Map) {
          map = (data['outing'] as Map).cast<String, dynamic>();
        } else if (data is Map && data['data'] is Map) {
          map = (data['data'] as Map).cast<String, dynamic>();
        } else {
          map = (data as Map).cast<String, dynamic>();
        }
        return Outing.fromJson(map);
      }
      throw Exception('POST /api/outings -> ${res.statusCode}: ${res.body}');
    } on SocketException catch (_) {
      // 👇 fallback to Outbox when offline
      final clientId = await OutboxService.instance.enqueueOutingCreate(
        title: draft.title,
        date: draft.startsAt, // 'date' expected by server (vs. startsAt UI model)
        location: draft.location,
        description: draft.description,
      );
      return Outing(
        id: 'local-$clientId',
        title: draft.title,
        location: draft.location,
        startsAt: draft.startsAt,
        description: draft.description,
        isLocalOnly: true, // optional field in Outing model
      );
    }
  }

  /// Updates an outing online when possible. If offline, we enqueue an
  /// Outbox "outingUpdate" task for background delivery.
  Future<void> updateOuting(String outingId, Map<String, dynamic> patch) async {
    try {
      final res = await _api.patchJson('/api/outings/$outingId', patch);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'PATCH /api/outings/$outingId -> ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (_) {
      // 👇 fallback to Outbox when offline
      await OutboxService.instance.enqueueOutingUpdate(
        outingId: outingId,
        patch: patch,
      );
    }
  }
}
