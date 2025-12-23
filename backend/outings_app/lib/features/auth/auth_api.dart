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

  /// POST /api/auth/login  (fallback: /auth/login)
  /// Accepts { email, password }
  /// Returns AuthResult(token, userId)
  Future<AuthResult> login({
    required String email,
    required String password,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final primary = Uri.parse('$_base/api/auth/login');
    final fallback = Uri.parse('$_base/auth/login'); // legacy (no /api)

    http.Response res = await _postJsonWithLogging(
      uri: primary,
      body: {'email': email, 'password': password},
      timeout: timeout,
      label: 'login(primary)',
    );

    if (res.statusCode == 404) {
      res = await _postJsonWithLogging(
        uri: fallback,
        body: {'email': email, 'password': password},
        timeout: timeout,
        label: 'login(fallback)',
      );
    }

    _throwOnNon2xx(res, defaultMsg: 'Login failed');

    final body = _decodeBodyAsMap(res.body);
    final token = _firstString(body, const ['token', 'jwt', 'accessToken']);
    if (token == null || token.isEmpty) {
      throw Exception('Malformed response from server (missing token).');
    }

    String? userId =
        _firstString(body, const ['userId']) ??
        _firstString(body['user'] as Map<String, dynamic>?, const ['id']) ??
        _firstString(
          (body['data'] as Map?)?['user'] as Map<String, dynamic>?,
          const ['id'],
        );

    userId ??= await _fetchUserIdViaMe(token);
    if (userId == null || userId.isEmpty) {
      throw Exception('Could not determine user id from server.');
    }

    return AuthResult(token: token, userId: userId);
  }

  /// POST /api/auth/register  (fallback: /auth/register)
  /// Accepts { fullName, email, password }
  /// Returns AuthResult(token, userId)
  ///
  /// New behaviour:
  /// - If the register response includes a token, use it (old behaviour).
  /// - If it does NOT include a token but is 2xx, immediately call `login`
  ///   with the same credentials to obtain token + userId.
  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final primary = Uri.parse('$_base/api/auth/register');
    final fallback = Uri.parse('$_base/auth/register'); // legacy (no /api)

    http.Response res = await _postJsonWithLogging(
      uri: primary,
      body: {'fullName': fullName, 'email': email, 'password': password},
      timeout: timeout,
      label: 'register(primary)',
    );

    if (res.statusCode == 404) {
      res = await _postJsonWithLogging(
        uri: fallback,
        body: {'fullName': fullName, 'email': email, 'password': password},
        timeout: timeout,
        label: 'register(fallback)',
      );
    }

    // If email is already taken, surface a clear message.
    if (res.statusCode == 409) {
      _throwOnNon2xx(res, defaultMsg: 'Email already in use.');
    }

    // For any other non-2xx, let the existing helper throw a detailed error.
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwOnNon2xx(res, defaultMsg: 'Registration failed');
    }

    // Try to read a token from the register response, like before.
    final body = _decodeBodyAsMap(res.body);
    final token = _firstString(body, const ['token', 'jwt', 'accessToken']);

    if (token == null || token.isEmpty) {
      // ✅ Backend created the user but didn't return a token.
      // Immediately log in with the same credentials to get token + userId.
      return login(email: email, password: password, timeout: timeout);
    }

    // Same userId logic as in login()
    String? userId =
        _firstString(body, const ['userId']) ??
        _firstString(body['user'] as Map<String, dynamic>?, const ['id']) ??
        _firstString(
          (body['data'] as Map?)?['user'] as Map<String, dynamic>?,
          const ['id'],
        );

    userId ??= await _fetchUserIdViaMe(token);
    if (userId == null || userId.isEmpty) {
      throw Exception('Could not determine user id from server.');
    }

    return AuthResult(token: token, userId: userId);
  }

  Future<String?> _fetchUserIdViaMe(String token) async {
    final primary = Uri.parse('$_base/api/auth/me');
    final fallback = Uri.parse('$_base/auth/me'); // legacy (no /api)

    final resPrimary = await _getWithLogging(
      uri: primary,
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      label: 'me(primary)',
      timeout: const Duration(seconds: 15),
    );

    http.Response res = resPrimary;
    if (res.statusCode == 404) {
      res = await _getWithLogging(
        uri: fallback,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
        label: 'me(fallback)',
        timeout: const Duration(seconds: 15),
      );
    }

    if (res.statusCode != 200) return null;

    final decoded = _decodeBodyAsMap(res.body);
    final user = decoded['user'];
    if (user is Map<String, dynamic>) {
      return _firstString(user, const ['id']);
    }
    return null;
  }

  // ------------ Low-level helpers ------------

  void _throwOnNon2xx(http.Response res, {required String defaultMsg}) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    try {
      final m = jsonDecode(res.body);
      final msg =
          _firstString(m as Map<String, dynamic>?, const [
            'error',
            'message',
          ]) ??
          defaultMsg;
      throw Exception(msg);
    } catch (_) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Map<String, dynamic> _decodeBodyAsMap(String body) {
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Malformed response from server.');
    }
    return decoded;
  }

  Future<http.Response> _postJsonWithLogging({
    required Uri uri,
    required Map<String, dynamic> body,
    required Duration timeout,
    required String label,
  }) async {
    try {
      // ignore: avoid_print
      print('🔐 AuthApi $_base → POST $label: $uri');
      return await http
          .post(
            uri,
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on SocketException {
      throw Exception('Cannot reach server at ${AppConfig.apiBaseUrl}');
    } on HttpException catch (e) {
      throw Exception('HTTP error: $e');
    } on TlsException catch (e) {
      throw Exception('TLS error: $e');
    }
  }

  Future<http.Response> _getWithLogging({
    required Uri uri,
    required Map<String, String> headers,
    required String label,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      // ignore: avoid_print
      print('🔐 AuthApi $_base → GET $label: $uri');
      return await http
          .get(
            uri,
            headers: {...headers, HttpHeaders.acceptHeader: 'application/json'},
          )
          .timeout(timeout);
    } on SocketException {
      throw Exception('Cannot reach server at ${AppConfig.apiBaseUrl}');
    } on HttpException catch (e) {
      throw Exception('HTTP error: $e');
    } on TlsException catch (e) {
      throw Exception('TLS error: $e');
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
  }
}
