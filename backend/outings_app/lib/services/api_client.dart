// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, this.authToken});
  final String baseUrl;
  String? authToken;

  Map<String, String> _headers({Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $authToken';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  /// Public helper so call-sites that expect headers can use this.
  Map<String, String> buildHeaders([Map<String, String>? extra]) =>
      _headers(extra: extra);

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path')
          .replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  Future<http.Response> get(String path, {Map<String, dynamic>? query}) {
    return http.get(_u(path, query), headers: _headers());
  }

  Future<http.Response> postJson(String path, Map<String, dynamic> body) {
    return http.post(_u(path), headers: _headers(), body: jsonEncode(body));
  }

  Future<http.Response> putJson(String path, Map<String, dynamic> body) {
    return http.put(_u(path), headers: _headers(), body: jsonEncode(body));
  }

  /// Handy if you later want to use ApiClient for PATCH too.
  Future<http.Response> patchJson(String path, Map<String, dynamic> body) {
    return http.patch(_u(path), headers: _headers(), body: jsonEncode(body));
  }

  /// DELETE (no body)
  Future<http.Response> delete(String path) {
    return http.delete(_u(path), headers: _headers());
  }

  /// Multipart helper
  ///
  /// - `fields`: regular form fields
  /// - `files`: map of fieldName -> ByteStream (MUST have a known length)
  /// - `filenames`: map of fieldName -> filename (default 'upload.jpg')
  Future<http.StreamedResponse> postMultipart(
    String path, {
    required Map<String, String> fields,
    required Map<String, http.ByteStream> files,
    required Map<String, String> filenames,
    Map<String, String>? query,
  }) async {
    final req = http.MultipartRequest('POST', _u(path, query));

    // Do NOT set Content-Type here; MultipartRequest will set the proper boundary.
    // Add auth header if present.
    if (authToken != null && authToken!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $authToken';
    }

    // Fields
    fields.forEach((k, v) {
      req.fields.putIfAbsent(k, () => v);
    });

    // Files
    for (final entry in files.entries) {
      final field = entry.key;
      final stream = entry.value;
      final filename = filenames[field] ?? 'upload.jpg';
      final length = await stream.length;
      req.files.add(
        http.MultipartFile(field, stream, length, filename: filename),
      );
    }

    return req.send();
  }
}
