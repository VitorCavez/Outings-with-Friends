// lib/features/auth/auth_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';

class AuthResult {
  final String token;
  final String userId;
  const AuthResult({required this.token, required this.userId});
}

class AuthApi {
  final String _base = AppConfig.apiBaseUrl;

  /// Calls POST /api/auth/login and returns the auth token + userId.
  /// Tolerates a few response shapes:
  ///  - { token, user: { id } }
  ///  - { token, userId }
  ///  - { jwt/accessToken, data: { user: { id } } }
  Future<AuthResult> login({
    required String email,
    required String password,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final uri = Uri.parse('$_base/api/auth/login');

    late http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(timeout);
    } on SocketException {
      throw Exception('Cannot reach server at ${AppConfig.apiBaseUrl}');
    } on HttpException catch (e) {
      throw Exception('HTTP error: $e');
    } on TlsException catch (e) {
      throw Exception('TLS error: $e');
    }

    // Non-2xx → bubble up backend error text if present
    if (res.statusCode < 200 || res.statusCode >= 300) {
      try {
        final m = jsonDecode(res.body);
        final msg = _firstString(m, const ['error', 'message']) ?? 'Login failed';
        throw Exception(msg);
      } catch (_) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
    }

    // Parse body (be tolerant to different shapes)
    final dynamic decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Malformed response from server.');
    }
    final Map<String, dynamic> body = decoded;

    final token = _firstString(body, const ['token', 'jwt', 'accessToken']);
    if (token == null || token.isEmpty) {
      throw Exception('Malformed response from server (missing token).');
    }

    // Try to extract userId from common shapes
    String? userId =
        _firstString(body, const ['userId']) ??
        _firstString(body['user'] as Map<String, dynamic>?, const ['id']) ??
        _firstString((body['data'] as Map?)?['user'] as Map<String, dynamic>?, const ['id']);

    // If backend didn’t include userId, fetch it via /me
    if (userId == null || userId.isEmpty) {
      userId = await _fetchUserIdViaMe(token);
      if (userId == null || userId.isEmpty) {
        throw Exception('Could not determine user id from server.');
      }
    }

    return AuthResult(token: token, userId: userId);
  }

  Future<String?> _fetchUserIdViaMe(String token) async {
    final uri = Uri.parse('$_base/api/auth/me');
    try {
      final res = await http.get(
        uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.acceptHeader: 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return null;

      final dynamic decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;

      final user = decoded['user'];
      if (user is Map<String, dynamic>) {
        return _firstString(user, const ['id']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Safely pulls the first non-empty string value for any of [keys] from [map].
  String? _firstString(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final k in keys) {
      final v = map[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
=======
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
