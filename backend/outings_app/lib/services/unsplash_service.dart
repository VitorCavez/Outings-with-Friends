// lib/services/unsplash_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class UnsplashPhoto {
  final String id;
  final String thumbUrl;
  final String fullUrl;
  final String author;
  UnsplashPhoto({
    required this.id,
    required this.thumbUrl,
    required this.fullUrl,
    required this.author,
  });

  factory UnsplashPhoto.fromJson(Map<String, dynamic> j) {
    return UnsplashPhoto(
      id: j['id'] as String,
      thumbUrl: j['urls']?['small'] as String? ?? j['urls']?['thumb'] as String? ?? '',
      fullUrl: j['urls']?['regular'] as String? ?? j['urls']?['full'] as String? ?? '',
      author: (j['user']?['name'] as String?) ?? 'Unknown',
    );
  }
}

class UnsplashService {
  UnsplashService(this.api);
  final ApiClient api;

  /// GET /api/unsplash/search?query=...
  Future<List<UnsplashPhoto>> search(String query, {int page = 1}) async {
    final r = await api.get('/api/unsplash/search', query: {
      'query': query,
      'page': page,
    });
    if (r.statusCode != 200) {
      throw Exception('Unsplash search failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    final List data = (map['data'] ?? map['results'] ?? []) as List;
    return data.map((e) => UnsplashPhoto.fromJson(e as Map<String, dynamic>)).toList();
  }
}
