// lib/services/favorites_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class FavoritesService {
  FavoritesService(this.api);
  final ApiClient api;

  /// POST /api/outings/:outingId/favorite
  Future<FavoriteItem> favorite(String outingId) async {
    final r = await api.postJson('/api/outings/$outingId/favorite', {});
    if (r.statusCode != 201) {
      throw Exception('favorite failed (${r.statusCode}) ${r.body}');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return FavoriteItem.fromJson(map['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/outings/:outingId/favorite
  Future<void> unfavorite(String outingId) async {
    final req = http.Request('DELETE', Uri.parse('${api.baseUrl}/api/outings/$outingId/favorite'));
    if (api.authToken != null && api.authToken!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${api.authToken}';
    }
    final streamed = await req.send();
    final code = streamed.statusCode;
    if (code != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception('unfavorite failed ($code) $body');
    }
  }

  /// GET /api/users/me/favorites?limit=&offset=
  Future<FavoritesListResponse> listMine({int limit = 25, int offset = 0}) async {
    final r = await api.get('/api/users/me/favorites', query: {
      'limit': limit,
      'offset': offset,
    });
    if (r.statusCode != 200) {
      throw Exception('list favorites failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return FavoritesListResponse.fromJson(map);
  }
}

/// --- DTOs ---
class FavoriteItem {
  FavoriteItem({
    required this.id,
    required this.userId,
    required this.outingId,
    required this.createdAt,
    this.outing,
  });

  final String id;
  final String userId;
  final String outingId;
  final DateTime createdAt;
  final FavoriteOutingSnapshot? outing;

  factory FavoriteItem.fromJson(Map<String, dynamic> j) {
    return FavoriteItem(
      id: j['id'],
      userId: j['userId'],
      outingId: j['outingId'],
      createdAt: DateTime.parse(j['createdAt']),
      outing: j['outing'] != null
          ? FavoriteOutingSnapshot.fromJson(j['outing'] as Map<String, dynamic>)
          : null,
    );
  }
}

class FavoriteOutingSnapshot {
  FavoriteOutingSnapshot({
    required this.id,
    required this.title,
    required this.outingType,
    this.locationName,
    this.address,
    this.dateTimeStart,
    this.dateTimeEnd,
    this.coverImageUrl,
    this.coverImageSource,
  });

  final String id;
  final String title;
  final String outingType;
  final String? locationName;
  final String? address;
  final DateTime? dateTimeStart;
  final DateTime? dateTimeEnd;
  final String? coverImageUrl;
  final String? coverImageSource;

  factory FavoriteOutingSnapshot.fromJson(Map<String, dynamic> j) {
    DateTime? _dt(String? v) => v == null ? null : DateTime.parse(v);
    return FavoriteOutingSnapshot(
      id: j['id'],
      title: j['title'],
      outingType: j['outingType'],
      locationName: j['locationName'],
      address: j['address'],
      dateTimeStart: _dt(j['dateTimeStart']?.toString()),
      dateTimeEnd: _dt(j['dateTimeEnd']?.toString()),
      coverImageUrl: j['coverImageUrl'],
      coverImageSource: j['coverImageSource'],
    );
  }
}

class FavoritesListResponse {
  FavoritesListResponse({
    required this.ok,
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  final bool ok;
  final int total;
  final int limit;
  final int offset;
  final List<FavoriteItem> items;

  factory FavoritesListResponse.fromJson(Map<String, dynamic> j) {
    final data = (j['data'] as List)
        .map((e) => FavoriteItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final meta = (j['meta'] as Map?) ?? {};
    return FavoritesListResponse(
      ok: j['ok'] == true,
      total: (meta['total'] ?? j['total'] ?? data.length) as int,
      limit: (meta['limit'] ?? j['limit'] ?? data.length) as int,
      offset: (meta['offset'] ?? j['offset'] ?? 0) as int,
      items: data,
    );
  }
}
