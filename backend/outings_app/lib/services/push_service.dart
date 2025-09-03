// lib/services/push_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:outings_app/config/app_config.dart';

/// Minimal service to register/unregister the device FCM token with your backend.
/// Firebase initialization + permission prompts are handled in main.dart.
class PushService {
  static String get _base => AppConfig.apiBaseUrl;

  /// Register/update the current device's token for a user.
  static Future<void> registerToken({
    required String userId,
    required String token,
  }) async {
    final uri = Uri.parse('$_base/api/push/register');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'fcmToken': token}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('registerToken failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Optional: call on logout to clear token on the server (if you expose this route).
  static Future<void> unregisterToken({required String userId}) async {
    final uri = Uri.parse('$_base/api/push/unregister');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('unregisterToken failed: ${res.statusCode} ${res.body}');
    }
  }
}
