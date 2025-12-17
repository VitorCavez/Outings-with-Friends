// lib/features/discover/discover_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/geocoding_service.dart';
import '../../services/discover_service.dart';
import '../../models/discover_models.dart';
import '../../features/auth/auth_provider.dart';
import '../../theme/app_theme.dart'; // BrandColors extension

/// ---- Persistence Keys ----
const _kViewKey = 'discover.view'; // 'map' | 'list'
const _kCenterLatKey = 'discover.centerLat';
const _kCenterLngKey = 'discover.centerLng';
const _kZoomKey = 'discover.zoom';
const _kRadiusKmKey = 'discover.radiusKm';
const _kTypesCsvKey = 'discover.typesCsv'; // "Food,Hike"

/// ---- Cached feed keys ----
const _kCacheFeatured = 'discover.cache.featured';
const _kCacheSuggested = 'discover.cache.suggested';
const _kCacheTs = 'discover.cache.ts';

/// ---- Map style IDs (source) ----
const _kSourceId = 'outings-source';

/// UI model (simple) for rendering cards & map pins.
class Outing {
  final String id;
  final String title;
  final String subtitle;
  final String type; // e.g., "Drinks", "Hike", "Food", etc.
  final double lat;
  final double lng;
  final String imageUrl;

  const Outing({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.lat,
    required this.lng,
    required this.imageUrl,
  });

  factory Outing.fromModel(OutingModel m) => Outing(
    id: m.id,
    title: m.title,
    subtitle: m.subtitle ?? '',
    type: m.type,
    lat: m.lat,
    lng: m.lng,
    imageUrl:
        m.imageUrl ??
        'https://images.unsplash.com/photo-1532635042-6d4cb7a8270a?w=800&q=80',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'type': type,
    'lat': lat,
    'lng': lng,
    'imageUrl': imageUrl,
  };

  factory Outing.fromJson(Map<String, dynamic> j) => Outing(
    id: j['id'] as String,
    title: j['title'] as String,
    subtitle: (j['subtitle'] ?? '') as String,
    type: j['type'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    imageUrl: j['imageUrl'] as String,
  );
}

enum _DiscoverView { map, list }

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  _DiscoverView _view = _DiscoverView.map;

  // Connectivity
  bool _isOffline = false;
  StreamSubscription<dynamic>? _connSub;

  // Map + clustering
  mb.MapboxMap? _mapboxMap;
  mb.PointAnnotationManager? _pointManager; // temp red pin
  mb.PointAnnotation? _searchAnnotation;
  bool _locationEnabled = false;
  bool _isCentering = false;

  // Live data
  final _discover = DiscoverService();
  List<Outing> _featured = const [];
  List<Outing> _suggested = const [];
  bool _loading = false;
  String? _error;

  // Filters
  DiscoverFilters _filters = const DiscoverFilters(radiusKm: 10, limit: 20);
  final Set<String> _selectedTypes = <String>{};
  geo.Position? _lastPosition;
  double _lastZoom = 12.0;

  // Geocoding (OpenCage)
  final _geo = GeocodingService();
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _suggestionsDebounce;
  bool _searching = false;

  // Suggestions
  List<PlaceResult> _suggestions = [];
  bool _showSuggestions = false;

  // Default camera over Dublin (no const)
  final mb.CameraOptions _defaultCamera = mb.CameraOptions(
    center: mb.Point(coordinates: mb.Position(-6.2603, 53.3498)), // lng, lat
    zoom: 12.0,
    pitch: 0.0,
    bearing: 0.0,
  );

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _restoreState().then((_) {
      _ensureLocationPermission().then((_) => _bootstrapData());
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _suggestionsDebounce?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _pointManager = null;
    _mapboxMap = null;
    super.dispose();
  }

  /// ---- Connectivity watcher ----
  Future<void> _initConnectivity() async {
    final initial = await Connectivity().checkConnectivity();
    _normalizeAndSetOffline(initial);
    _connSub = Connectivity().onConnectivityChanged.listen((
      dynamic event,
    ) async {
      final wasOffline = _isOffline;
      _normalizeAndSetOffline(event);
      if (!mounted) return;

      if (wasOffline && !_isOffline) {
        _showSnack('Back online. Refreshing…');
        await _loadDiscover();
      } else if (!wasOffline && _isOffline) {
        _showSnack('You are offline. Showing cached results.');
        await _loadCachedDiscover();
      }
    });
  }

  void _normalizeAndSetOffline(dynamic connectivityEvent) {
    List<ConnectivityResult> results;
    if (connectivityEvent is List<ConnectivityResult>) {
      results = connectivityEvent;
    } else if (connectivityEvent is ConnectivityResult) {
      results = <ConnectivityResult>[connectivityEvent];
    } else {
      results = const <ConnectivityResult>[];
    }
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline != _isOffline) {
      setState(() => _isOffline = offline);
    }
  }

  /// ---- Persistence: load previously saved state ----
  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();

    // View
    final v = prefs.getString(_kViewKey);
    if (v == 'list') _view = _DiscoverView.list;

    // Center + zoom
    final savedLat = prefs.getDouble(_kCenterLatKey);
    final savedLng = prefs.getDouble(_kCenterLngKey);
    final savedZoom = prefs.getDouble(_kZoomKey);
    if (savedLat != null && savedLng != null) {
      _lastPosition = geo.Position(
        latitude: savedLat,
        longitude: savedLng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }
    if (savedZoom != null) _lastZoom = savedZoom;

    // Filters
    final savedRadius = prefs.getDouble(_kRadiusKmKey);
    final typesCsv = prefs.getString(_kTypesCsvKey);
    final types = <String>{};
    if (typesCsv != null && typesCsv.trim().isNotEmpty) {
      types.addAll(
        typesCsv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    }
    _selectedTypes
      ..clear()
      ..addAll(types);
    _filters = DiscoverFilters(
      radiusKm: savedRadius ?? _filters.radiusKm,
      limit: _filters.limit,
      types: _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
    );

    // Optimistic UI
    await _loadCachedDiscover(showLoading: false);

    setState(() {});
  }

  Future<void> _bootstrapData() async {
    geo.Position? pos = _lastPosition;
    if (pos == null) {
      try {
        if (_locationEnabled) {
          // ✅ use locationSettings instead of deprecated desiredAccuracy
          pos = await geo.Geolocator.getCurrentPosition(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.medium,
            ),
          );
        }
      } catch (_) {}
      pos ??= geo.Position(
        latitude: 53.3498,
        longitude: -6.2603,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
      _lastPosition = pos;
    }

    if (_isOffline) {
      await _loadCachedDiscover();
    } else {
      await _loadDiscover();
    }
  }

  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationEnabled = false);
      return;
    }

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.deniedForever ||
        permission == geo.LocationPermission.denied) {
      setState(() => _locationEnabled = false);
      return;
    }

    setState(() => _locationEnabled = true);
  }

  /// ---- Cache helpers ----
  Future<void> _saveDiscoverCache({
    required List<Outing> featured,
    required List<Outing> suggested,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCacheFeatured,
      jsonEncode(featured.map((o) => o.toJson()).toList()),
    );
    await prefs.setString(
      _kCacheSuggested,
      jsonEncode(suggested.map((o) => o.toJson()).toList()),
    );
    await prefs.setInt(_kCacheTs, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _loadCachedDiscover({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final fStr = prefs.getString(_kCacheFeatured);
    final sStr = prefs.getString(_kCacheSuggested);

    if (fStr != null && sStr != null) {
      try {
        final fList = (jsonDecode(fStr) as List)
            .map((e) => Outing.fromJson(e as Map<String, dynamic>))
            .toList();
        final sList = (jsonDecode(sStr) as List)
            .map((e) => Outing.fromJson(e as Map<String, dynamic>))
            .toList();

        setState(() {
          _featured = fList;
          _suggested = sList;
          _loading = false;
          _error = null;
        });

        // Populate map if ready
        await _refreshClusteredData([..._featured, ..._suggested]);
      } catch (_) {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ---- Style-safe helpers ----

  Future<void> _withStyle(
    Future<void> Function(mb.StyleManager style) action, {
    int retries = 4,
    Duration delay = const Duration(milliseconds: 180),
  }) async {
    if (!mounted || _mapboxMap == null) return;
    int attempts = 0;
    Object? lastError;

    while (attempts <= retries && mounted && _mapboxMap != null) {
      try {
        final style = _mapboxMap!.style;
        await action(style);
        return;
      } catch (e) {
        lastError = e;
        final msg = e.toString();
        final shouldRetry =
            msg.contains('channel-error') ||
            msg.contains('styleSourceExists') ||
            msg.contains('disposed') ||
            msg.contains('StyleManager');
        if (!shouldRetry || attempts == retries) break;
        await Future.delayed(delay);
      }
      attempts++;
    }
    debugPrint('Map style action failed after retries: $lastError');
  }

  /// Ensure GeoJSON source exists (clustered)
  Future<void> _ensureSource() async {
    await _withStyle((style) async {
      final exists = await style.styleSourceExists(_kSourceId);
      if (!exists) {
        final source = mb.GeoJsonSource(
          id: _kSourceId,
          cluster: true,
          clusterRadius: 50,
          clusterMaxZoom: 14,
        );
        await style.addSource(source);
      }
    });
  }

  /// Feed outings into the GeoJSON source
  Future<void> _refreshClusteredData(List<Outing> items) async {
    if (!mounted || _mapboxMap == null) return;
    await _withStyle((style) async {
      final exists = await style.styleSourceExists(_kSourceId);
      if (!exists) {
        final source = mb.GeoJsonSource(
          id: _kSourceId,
          cluster: true,
          clusterRadius: 50,
          clusterMaxZoom: 14,
        );
        await style.addSource(source);
      }

      final features = items.map((o) {
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [o.lng, o.lat],
          },
          'properties': {'id': o.id, 'title': o.title, 'type': o.type},
        };
      }).toList();

      final fc = {'type': 'FeatureCollection', 'features': features};
      await style.setStyleSourceProperty(_kSourceId, 'data', jsonEncode(fc));
    });
  }

  // ---- Map setup ----
  void _applySavedCameraOrDefault() async {
    if (_lastPosition != null) {
      await _mapboxMap?.setCamera(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(
              _lastPosition!.longitude,
              _lastPosition!.latitude,
            ),
          ),
          zoom: _lastZoom,
        ),
      );
    } else {
      await _mapboxMap?.setCamera(_defaultCamera);
      _lastZoom = _defaultCamera.zoom ?? 12.0;
    }
  }

  void _onMapCreated(mb.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // User puck
    try {
      await _mapboxMap?.location.updateSettings(
        mb.LocationComponentSettings(
          enabled: _locationEnabled,
          puckBearingEnabled: true,
          pulsingEnabled: true,
          showAccuracyRing: true,
        ),
      );
    } catch (_) {}

    // Annotation manager
    try {
      _pointManager = await _mapboxMap?.annotations
          .createPointAnnotationManager();
    } catch (_) {
      _pointManager = null;
    }

    _applySavedCameraOrDefault();

    await _ensureSource();

    if (_featured.isNotEmpty || _suggested.isNotEmpty) {
      await _refreshClusteredData([..._featured, ..._suggested]);
    }
  }

  Future<void> _centerOnUser() async {
    if (_isCentering) return;
    setState(() => _isCentering = true);

    try {
      if (!_locationEnabled) {
        await _ensureLocationPermission();
      }
      if (!_locationEnabled) return;

      // ✅ use locationSettings instead of deprecated desiredAccuracy
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      _lastPosition = pos;

      _lastZoom = 14.0;
      await _mapboxMap?.flyTo(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(pos.longitude, pos.latitude),
          ),
          zoom: _lastZoom,
          pitch: 0.0,
        ),
        mb.MapAnimationOptions(duration: 800),
      );

      await _saveCenter(pos.latitude, pos.longitude, zoom: _lastZoom);

      await _loadDiscover();
    } finally {
      if (mounted) setState(() => _isCentering = false);
    }
  }

  // ---- Search (debounced suggestions) ----
  void _onSearchChanged(String value) {
    _suggestionsDebounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    _suggestionsDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _fetchSuggestions(value),
    );

    setState(() {}); // updates clear button visibility
  }

  Future<void> _fetchSuggestions(String query) async {
    if (_isOffline) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      _showSnack('Offline: suggestions unavailable.');
      return;
    }

    final resp = await _geo.forward(
      address: query.trim(),
      limit: 5,
      language: 'en',
    );

    if (!mounted) return;

    if (!resp.ok) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    setState(() {
      _suggestions = resp.results;
      _showSuggestions = _suggestions.isNotEmpty;
    });
  }

  Future<void> _forwardGeocodeAndCenter(String query) async {
    if (query.trim().isEmpty) return;
    if (_isOffline) {
      _showSnack('Offline: can’t search now.');
      return;
    }

    setState(() => _searching = true);

    final resp = await _geo.forward(
      address: query.trim(),
      limit: 1,
      language: 'en',
    );

    if (!mounted) return;

    setState(() => _searching = false);

    if (!resp.ok) {
      _showSnack(resp.error ?? 'Geocoding failed');
      return;
    }
    if (resp.results.isEmpty) {
      _showSnack('No results for “$query”.');
      return;
    }

    final best = resp.results.first;
    await _setSearchPinAndCenter(best.coordinates.lat, best.coordinates.lng);
    _lastZoom = 14.0;
    await _saveCenter(
      best.coordinates.lat,
      best.coordinates.lng,
      zoom: _lastZoom,
    );
    _showSnack('📍 ${best.formatted}');

    _lastPosition = geo.Position(
      latitude: best.coordinates.lat,
      longitude: best.coordinates.lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    await _loadDiscover();
  }

  Future<void> _onSuggestionTap(PlaceResult r) async {
    if (_isOffline) {
      _showSnack('Offline: can’t search now.');
      return;
    }

    _searchCtl.text = r.formatted;
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
    if (_searchFocus.hasFocus) _searchFocus.unfocus();

    await _setSearchPinAndCenter(r.coordinates.lat, r.coordinates.lng);
    _lastZoom = 14.0;
    await _saveCenter(r.coordinates.lat, r.coordinates.lng, zoom: _lastZoom);
    _showSnack('📍 ${r.formatted}');

    _lastPosition = geo.Position(
      latitude: r.coordinates.lat,
      longitude: r.coordinates.lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    await _loadDiscover();
  }

  Future<void> _setSearchPinAndCenter(double lat, double lng) async {
    if (_mapboxMap == null || _pointManager == null) return;

    if (_searchAnnotation != null) {
      try {
        await _pointManager!.delete(_searchAnnotation!);
      } catch (_) {}
      _searchAnnotation = null;
    }

    try {
      _searchAnnotation = await _pointManager!.create(
        mb.PointAnnotationOptions(
          geometry: mb.Point(coordinates: mb.Position(lng, lat)),
          iconSize: 1.2,
          textField: 'Selected',
          textOffset: [0, 1.6],
          textSize: 12.0,
          textColor: const Color(0xFFFF0000).toARGB32(),
        ),
      );
    } catch (_) {}

    await _mapboxMap?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(lng, lat)),
        zoom: 14.0,
        pitch: 0.0,
      ),
      mb.MapAnimationOptions(duration: 700),
    );
  }

  void _clearSearch() {
    _searchCtl.clear();
    _suggestionsDebounce?.cancel();
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  void _dismissSuggestionsAndKeyboard() {
    setState(() {
      _showSuggestions = false;
    });
    if (_searchFocus.hasFocus) _searchFocus.unfocus();
  }

  void _showOutingBottomSheet(Outing o) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _OutingPreviewSheet(outing: o),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- Filters UI ----
  void _openFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FiltersSheet(
        initialRadiusKm: _filters.radiusKm ?? 10,
        selectedTypes: _selectedTypes,
      ),
    );

    if (result == null) return;

    setState(() {
      _filters = DiscoverFilters(
        radiusKm: result.radiusKm,
        limit: _filters.limit,
        types: result.types.isEmpty ? null : result.types.toList(),
      );
      _selectedTypes
        ..clear()
        ..addAll(result.types);
    });

    await _saveFilters(
      radiusKm: _filters.radiusKm ?? 10,
      typesCsv: _selectedTypes.join(','),
    );

    await _loadDiscover();
  }

  String? _jwt() {
    try {
      final auth = context.read<AuthProvider?>();
      final dyn = auth as dynamic;
      return (dyn?.authToken ?? dyn?.token ?? dyn?.accessToken ?? dyn?.jwt)
          as String?;
    } catch (_) {
      return null;
    }
  }

  /// ---- Network load (with cache fallback) ----
  Future<void> _loadDiscover() async {
    if (_lastPosition == null) return;

    if (_isOffline) {
      await _loadCachedDiscover();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final effectiveFilters = DiscoverFilters(
        types: _selectedTypes.isNotEmpty ? _selectedTypes.toList() : null,
        radiusKm: _filters.radiusKm,
        limit: _filters.limit,
      );

      final resp = await _discover.fetchDiscover(
        lat: _lastPosition!.latitude,
        lng: _lastPosition!.longitude,
        filters: effectiveFilters,
        // removed undefined named parameter `authToken`; service should handle authorization internally
      );

      final featured = resp.featured.map(Outing.fromModel).toList();
      final suggested = resp.suggested.map(Outing.fromModel).toList();

      setState(() {
        _featured = featured;
        _suggested = suggested;
        _loading = false;
      });

      await _saveDiscoverCache(featured: _featured, suggested: _suggested);

      await _refreshClusteredData([..._featured, ..._suggested]);
    } catch (e) {
      await _loadCachedDiscover();
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMap = _view == _DiscoverView.map;

    final mainContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _featured.isEmpty && _suggested.isEmpty
        ? _ErrorState(message: _error!, onRetry: _loadDiscover)
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isMap ? _buildMapView(cs) : _buildListView(cs),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Outings'),
        actions: [
          IconButton(
            tooltip: 'My Outings',
            icon: const Icon(Icons.list_alt),
            onPressed: () => context.go('/my-outings'),
          ),
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: CupertinoSegmentedControl<_DiscoverView>(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              groupValue: _view,
              children: const {
                _DiscoverView.map: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Map'),
                ),
                _DiscoverView.list: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('List'),
                ),
              },
              onValueChanged: (v) async {
                setState(() => _view = v);
                await _saveView(v);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isMap
          ? FloatingActionButton.extended(
              onPressed: _centerOnUser,
              label: _isCentering
                  ? const Text('Locating...')
                  : const Text('My Location'),
              icon: const Icon(Icons.my_location),
            )
          : null,
      body: Stack(
        children: [
          Positioned.fill(child: mainContent),
          if (_isOffline) _buildOfflineBanner(cs),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner(ColorScheme cs) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: cs.onSecondaryContainer, size: 18),
              const SizedBox(width: 8),
              Text(
                'Offline — showing cached results',
                style: TextStyle(color: cs.onSecondaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapView(ColorScheme cs) {
    // Mapbox desktop support is limited; on Windows we just show
    // a friendly fallback and ask the user to use List view.
    if (!_isMobile) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text(
                "Map view isn't available on desktop yet.\n"
                "Use the List tab to browse nearby outings.",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final totalCount = _featured.length + _suggested.length;

    return Stack(
      children: [
        // Map widget
        mb.MapWidget(
          key: const ValueKey('map'),
          onMapCreated: _onMapCreated,
          cameraOptions: _defaultCamera,
          textureView: true,
        ),

        // Small gradient overlay for nicer UI
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 28,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black26, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ),

        // --- Search bar + suggestions ---
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  elevation: 3,
                  color: cs.surface,
                  surfaceTintColor: cs.surface,
                  shadowColor: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(Icons.search, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _searchCtl,
                            focusNode: _searchFocus,
                            onChanged: _onSearchChanged,
                            textInputAction: _isMobile
                                ? TextInputAction.done
                                : TextInputAction.search,
                            onEditingComplete: () {
                              _dismissSuggestionsAndKeyboard();
                              final q = _searchCtl.text.trim();
                              if (q.isNotEmpty) _forwardGeocodeAndCenter(q);
                            },
                            onSubmitted: (v) {
                              _dismissSuggestionsAndKeyboard();
                              if (v.trim().isNotEmpty) {
                                _forwardGeocodeAndCenter(v);
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Search a place or address',
                              hintStyle: TextStyle(color: cs.onSurfaceVariant),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_searching)
                          const Padding(
                            padding: EdgeInsets.only(right: 8.0),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (_searchCtl.text.isNotEmpty && !_searching)
                          IconButton(
                            icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                            onPressed: _clearSearch,
                          ),
                      ],
                    ),
                  ),
                ),

                // --- Suggestions list (top 5) ---
                if (_showSuggestions)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Material(
                      elevation: 3,
                      color: cs.surface,
                      surfaceTintColor: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: cs.outlineVariant),
                          itemBuilder: (context, index) {
                            final r = _suggestions[index];
                            final addr = r.formatted;
                            final lat = r.coordinates.lat.toStringAsFixed(5);
                            final lng = r.coordinates.lng.toStringAsFixed(5);
                            return ListTile(
                              dense: true,
                              title: Text(
                                addr,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$lat, $lng',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                              leading: Icon(
                                Icons.place_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                              onTap: () => _onSuggestionTap(r),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Results count chip (map view)
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 56.0),
              child: Chip(
                backgroundColor: cs.secondaryContainer,
                labelStyle: TextStyle(color: cs.onSecondaryContainer),
                avatar: Icon(
                  totalCount == 0 ? Icons.info_outline : Icons.list_alt,
                  size: 18,
                  color: cs.onSecondaryContainer,
                ),
                label: Text(
                  totalCount == 0
                      ? 'No outings found here. Try widening filters.'
                      : '$totalCount results',
                ),
                side: BorderSide.none,
              ),
            ),
          ),
        ),

        // Featured cards carousel
        if (_featured.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _featured.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final o = _featured[i];
                  return _FeaturedCard(
                    outing: o,
                    onTap: () async {
                      final changed = await context.push<bool>(
                        '/outings/${o.id}',
                      );
                      if (changed == true) {
                        await _loadDiscover();
                      }
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildListView(ColorScheme cs) {
    final subtle = TextStyle(color: cs.onSurfaceVariant);
    final labelStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );

    final content = <Widget>[
      // Filters summary row
      Row(
        children: [
          Icon(Icons.tune, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Radius: ${(_filters.radiusKm ?? 10).toStringAsFixed(0)} km'
            '${_selectedTypes.isNotEmpty ? '  •  Types: ${_selectedTypes.join(', ')}' : ''}',
            style: subtle,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _openFilters,
            icon: const Icon(Icons.filter_list),
            label: const Text('Filters'),
          ),
        ],
      ),
      const SizedBox(height: 8),

      // Featured
      Text('Featured', style: labelStyle),
      const SizedBox(height: 8),
      if (_featured.isEmpty)
        _EmptyRow(message: 'No featured outings right now.', subtle: subtle)
      else
        ..._featured.map(
          (o) => _ListCard(
            outing: o,
            onTap: () async {
              final changed = await context.push<bool>('/outings/${o.id}');
              if (changed == true) {
                await _loadDiscover();
              }
            },
          ),
        ),

      const SizedBox(height: 16),

      // Suggested
      Text('Suggested for you', style: labelStyle),
      const SizedBox(height: 8),
      if (_suggested.isEmpty)
        _EmptyRow(
          message: 'No suggestions. Try widening filters.',
          subtle: subtle,
        )
      else
        ..._suggested.map(
          (o) => _ListCard(
            outing: o,
            onTap: () async {
              final changed = await context.push<bool>('/outings/${o.id}');
              if (changed == true) {
                await _loadDiscover();
              }
            },
          ),
        ),
      const SizedBox(height: 40),
    ];

    return RefreshIndicator(
      onRefresh: _loadDiscover,
      child: ListView(
        key: const ValueKey('list'),
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: content,
      ),
    );
  }

  /// ---- Save helpers ----
  Future<void> _saveCenter(
    double lat,
    double lng, {
    required double zoom,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCenterLatKey, lat);
    await prefs.setDouble(_kCenterLngKey, lng);
    await prefs.setDouble(_kZoomKey, zoom);
  }

  Future<void> _saveFilters({
    required double radiusKm,
    required String typesCsv,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRadiusKmKey, radiusKm);
    await prefs.setString(_kTypesCsvKey, typesCsv);
  }

  Future<void> _saveView(_DiscoverView v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kViewKey, v == _DiscoverView.map ? 'map' : 'list');
  }
}

/// --- Small widgets / sheets ---

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: cs.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String message;
  final TextStyle? subtle;
  const _EmptyRow({required this.message, this.subtle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(message, style: subtle),
  );
}

class _FeaturedCard extends StatelessWidget {
  final Outing outing;
  final VoidCallback onTap;

  const _FeaturedCard({required this.outing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surface,
            boxShadow: const [
              BoxShadow(
                blurRadius: 8,
                offset: Offset(0, 4),
                color: Colors.black12,
              ),
            ],
            image: DecorationImage(
              image: NetworkImage(outing.imageUrl),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Colors.transparent, Colors.black54],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(
                  label: Text(
                    outing.type,
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.black45,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(height: 6),
                const SizedBox(height: 2),
                Text(
                  outing.title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
                Text(
                  outing.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  final Outing outing;
  final VoidCallback onTap;

  const _ListCard({required this.outing, required this.onTap});

  String _fmtLatLng(double lat, double lng) {
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cs.surface,
      surfaceTintColor: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            outing.imageUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            // 👇 New: graceful fallback instead of red error text
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 56,
                height: 56,
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.photo, color: cs.onSurfaceVariant, size: 24),
              );
            },
          ),
        ),
        title: Text(outing.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${outing.subtitle} • ${outing.type}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.outline),
      ),
    );
  }
}

class _OutingPreviewSheet extends StatelessWidget {
  final Outing outing;

  const _OutingPreviewSheet({required this.outing});

  String _fmtDate(DateTime dt) =>
      DateFormat('EEE, d MMM • HH:mm').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                image: DecorationImage(
                  image: NetworkImage(outing.imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    outing.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(outing.type),
                  backgroundColor: cs.secondaryContainer,
                  labelStyle: TextStyle(color: cs.onSecondaryContainer),
                  side: BorderSide.none,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                outing.subtitle,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.place, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${outing.lat.toStringAsFixed(5)}, ${outing.lng.toStringAsFixed(5)}',
                  style: TextStyle(color: cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    onPressed: () => Navigator.of(context).maybePop(),
                    label: const Text('View on Map'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ---- Filters Sheet ----

class _FilterResult {
  final double radiusKm;
  final Set<String> types;
  _FilterResult({required this.radiusKm, required this.types});
}

class _FiltersSheet extends StatefulWidget {
  final double initialRadiusKm;
  final Set<String> selectedTypes;

  const _FiltersSheet({
    required this.initialRadiusKm,
    required this.selectedTypes,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late double _radiusKm;
  late Set<String> _types;

  // Backend codes → nice labels
  static const Map<String, String> _typeLabels = {
    'food_and_drink': 'Food & drink',
    'outdoor': 'Outdoor',
    'concert': 'Concert',
    'sports': 'Sports',
    'movie': 'Movie',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialRadiusKm;

    // Keep only valid backend codes, drop any old human-readable labels
    _types = widget.selectedTypes
        .where((t) => _typeLabels.keys.contains(t))
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Radius',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_radiusKm.toStringAsFixed(0)} km',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _radiusKm,
                min: 2,
                max: 50,
                divisions: 48,
                label: '${_radiusKm.toStringAsFixed(0)} km',
                onChanged: (v) => setState(() => _radiusKm = v),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Types',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: _typeLabels.entries.map((entry) {
                  final code = entry.key; // e.g. "food_and_drink"
                  final label = entry.value; // e.g. "Food & drink"
                  final selected = _types.contains(code);

                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _types.add(code);
                        } else {
                          _types.remove(code);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop<_FilterResult>(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop<_FilterResult>(
                        _FilterResult(radiusKm: _radiusKm, types: _types),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
