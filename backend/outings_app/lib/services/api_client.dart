// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiClient {
  static String get _base => AppConfig.apiBaseUrl;

  static Uri _uri(String path, [Map<String, String>? query]) {
    // Ensure we don’t end up with a double slash
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_base$normalized').replace(queryParameters: query);
  }

  static Future<http.Response> postJson(
    String path,
    Map<String, Object?> body, {
    Map<String, String>? headers,
  }) {
    final h = <String, String>{'Content-Type': 'application/json', ...?headers};
    return http.post(_uri(path), headers: h, body: jsonEncode(body));
  }

  static Future<http.Response> getJson(
    String path, {
    Map<String, String>? headers,
  }) {
    final h = <String, String>{'Accept': 'application/json', ...?headers};
    return http.get(_uri(path), headers: h);
  }
}
