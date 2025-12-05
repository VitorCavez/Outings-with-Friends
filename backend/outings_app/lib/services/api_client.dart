// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A tiny HTTP client that automatically attaches the latest JWT.
/// - Pass either [authToken] (string) or a [tokenProvider] (preferred).
/// - If both are provided, [tokenProvider] wins on each request.
class ApiClient {
  ApiClient({required this.baseUrl, this.authToken, this.tokenProvider});

  final String baseUrl;
  String? authToken;
  final String Function()? tokenProvider;

  String? _currentToken() {
    try {
      final t = tokenProvider?.call();
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {
      // ignore
    }
    if (authToken != null && authToken!.isNotEmpty) return authToken;
    return null;
  }

  Map<String, String> _headers({Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final t = _currentToken();

    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }

    if (extra != null) h.addAll(extra);

    // DEBUG
    // ignore: avoid_print
    print(
      '🧪 ApiClient headers → hasAuth=${h.containsKey('Authorization')} '
      'len=${t?.length ?? 0}',
    );

    return h;
  }

  /// Public helper so call-sites that expect headers can use this.
  Map<String, String> buildHeaders([Map<String, String>? extra]) =>
      _headers(extra: extra);

  Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse(
    '$baseUrl$path',
  ).replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  Future<http.Response> get(String path, {Map<String, dynamic>? query}) {
    return http.get(_u(path, query), headers: _headers());
  }

  Future<http.Response> postJson(String path, Map<String, dynamic> body) {
    return http.post(_u(path), headers: _headers(), body: jsonEncode(body));
  }

  /// POST without body (e.g., toggle endpoints)
  Future<http.Response> post(String path) {
    return http.post(_u(path), headers: _headers());
  }

  Future<http.Response> putJson(String path, Map<String, dynamic> body) {
    return http.put(_u(path), headers: _headers(), body: jsonEncode(body));
  }

  Future<http.Response> patchJson(String path, Map<String, dynamic> body) {
    return http.patch(_u(path), headers: _headers(), body: jsonEncode(body));
  }

  Future<http.Response> delete(String path) {
    return http.delete(_u(path), headers: _headers());
  }

  /// Multipart helper
  Future<http.StreamedResponse> postMultipart(
    String path, {
    required Map<String, String> fields,
    required Map<String, http.ByteStream> files,
    required Map<String, String> filenames,
    Map<String, String>? query,
  }) async {
    final req = http.MultipartRequest('POST', _u(path, query));
    final t = _currentToken();
    if (t != null && t.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $t';
    }

    fields.forEach((k, v) => req.fields.putIfAbsent(k, () => v));

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
