// lib/services/images_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/outing_image.dart';
import 'api_client.dart';

class ImagesService {
  ImagesService(this.api);
  final ApiClient api;

  /// GET /api/outings/:outingId/images
  Future<List<OutingImage>> listOutingImages(String outingId) async {
    final r = await api.get('/api/outings/$outingId/images');
    if (r.statusCode != 200) {
      throw Exception('listOutingImages failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (map['data'] as List)
        .map((e) => OutingImage.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }

  /// POST /api/outings/:outingId/images (multipart/form-data)
  /// Pass either [file] (File) or [path] (String) — one is required.
  Future<OutingImage> uploadOutingImage(
    String outingId, {
    File? file,
    String? path,
    String filename = 'upload.jpg',
  }) async {
    final f = file ?? (path != null ? File(path) : null);
    if (f == null) throw ArgumentError('Provide either file or path');

    final length = await f.length();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${api.baseUrl}/api/outings/$outingId/images'),
    );

    // auth header
    if (api.authToken != null && api.authToken!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${api.authToken}';
    }

    request.files.add(http.MultipartFile(
      'image',
      http.ByteStream(f.openRead()),
      length,
      filename: filename,
    ));

    final resp = await request.send();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 201) {
      throw Exception('uploadOutingImage failed (${resp.statusCode}): $body');
    }
    final map = jsonDecode(body) as Map<String, dynamic>;
    return OutingImage.fromJson(map['data'] as Map<String, dynamic>);
  }

  /// ✅ NEW: Attach an image by URL (e.g., Unsplash)
  /// POST /api/outings/:outingId/images  (JSON body)
  /// { "imageUrl": "...", "imageSource": "unsplash" }
  Future<OutingImage> addFromUrl(
    String outingId, {
    required String imageUrl,
    String imageSource = 'unsplash',
  }) async {
    final r = await api.postJson(
      '/api/outings/$outingId/images',
      {
        'imageUrl': imageUrl,
        'imageSource': imageSource,
      },
    );
    if (r.statusCode != 201) {
      throw Exception('addFromUrl failed (${r.statusCode}): ${r.body}');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return OutingImage.fromJson(map['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/images/:imageId
  Future<bool> deleteImage(String imageId) async {
    // Direct DELETE
    final req = http.Request(
      'DELETE',
      Uri.parse('${api.baseUrl}/api/images/$imageId'),
    );
    if (api.authToken != null && api.authToken!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${api.authToken}';
    }
    final streamed = await req.send();
    return streamed.statusCode == 200;
  }
}
