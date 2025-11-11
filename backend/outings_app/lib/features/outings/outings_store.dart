// lib/features/outings/outings_store.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/id_map_service.dart';
import 'models/outing.dart';
import 'outings_repository.dart';

class OutingsStore extends ChangeNotifier {
  OutingsStore(this._repo) {
    // Listen for local -> server id reconciliations
    _idMapSub = IdMapService.instance.stream.listen(_onIdMapped);
  }

  final OutingsRepository _repo;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  final List<Outing> _items = [];
  List<Outing> get items => List.unmodifiable(_items);

  StreamSubscription? _idMapSub;

  @override
  void dispose() {
    _idMapSub?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _repo.fetchOutings();
      _items
        ..clear()
        ..addAll(data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> create(OutingDraft draft) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final created = await _repo.createOuting(draft);
      _items.insert(0, created);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // --- Reconciliation: replace local-<clientId> with <serverId> -------------
  void _onIdMapped(dynamic event) {
    if (event is! IdMapEvent) return;
    final idx = _items.indexWhere((o) => o.id == event.localId);
    if (idx == -1) return;

    final current = _items[idx];
    // Replace the item with a copy that only changes the id
    _items[idx] = Outing(
      id: event.serverId,
      title: current.title,
      location: current.location,
      startsAt: current.startsAt,
      description: current.description,
      isLocalOnly: false, // now synced
    );
    notifyListeners();
  }
}
