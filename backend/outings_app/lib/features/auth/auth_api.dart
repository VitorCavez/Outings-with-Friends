// lib/features/auth/auth_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/api_client.dart';

class AuthException implements Exception {
  final String message;
  final int? status;
  AuthException(this.message, {this.status});
  @override
  String toString() => 'AuthException($status): $message';
}

class AuthApi {
  /// POST /api/auth/login
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final http.Response res = await ApiClient.postJson('/api/auth/login', {
      'email': email,
      'password': password,
    });

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw AuthException(_extractError(res), status: res.statusCode);
  }

  /// POST /api/auth/register (ready if/when you hook up the Register screen)
  static Future<Map<String, dynamic>> register(
    Map<String, Object?> payload,
  ) async {
    final res = await ApiClient.postJson('/api/auth/register', payload);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw AuthException(_extractError(res), status: res.statusCode);
  }

  static String _extractError(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      final msg = body['error'] ?? body['message'];
      return (msg is String && msg.trim().isNotEmpty)
          ? msg
          : 'Request failed (${res.statusCode}).';
    } catch (_) {
      return 'Request failed (${res.statusCode}).';
    }
  }
}
