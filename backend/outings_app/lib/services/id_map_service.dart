// lib/services/id_map_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and broadcasts mappings like:
///   local-<clientId> -> <serverId>
class IdMapService {
  IdMapService._();
  static final IdMapService instance = IdMapService._();

  static const _prefsKey = 'idmap.outings';

  Map<String, String> _map = <String, String>{};
  final _controller = StreamController<IdMapEvent>.broadcast();

  /// Listen for mappings as they are created.
  Stream<IdMapEvent> get stream => _controller.stream;

  /// Load from SharedPreferences (idempotent).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final data = (jsonDecode(raw) as Map).cast<String, String>();
      _map = data;
    } catch (_) {
      // ignore parse errors
    }
  }

  /// Get a mapping if it exists.
  String? getServerIdFor(String localId) => _map[localId];

  /// Set and persist a mapping; notifies listeners.
  Future<void> setMapping({required String localId, required String serverId}) async {
    if (localId == serverId) return;
    _map[localId] = serverId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_map));
    _controller.add(IdMapEvent(localId: localId, serverId: serverId));
  }

  /// Remove mapping (rarely needed).
  Future<void> remove(String localId) async {
    _map.remove(localId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_map));
  }
}

@immutable
class IdMapEvent {
  final String localId;
  final String serverId;
  const IdMapEvent({required this.localId, required this.serverId});
}
