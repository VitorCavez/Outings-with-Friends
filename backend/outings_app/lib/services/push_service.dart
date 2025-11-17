// lib/services/push_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:outings_app/config/app_config.dart';

/// Paste-ready push helper:
/// - Call PushService.registerBackgroundHandler() ONCE in main() before runApp.
/// - Optionally call PushService.I.initForegroundHandlers() after startup.
/// - Ask permission from a Settings toggle with ensurePermission(...).
/// - After permission, call syncToken(userId) to register with your backend.
/// - Call disable(userId) to mute and clean up.
class PushService {
  PushService._();
  static final PushService I = PushService._();

  static bool _bgRegistered = false;

  static String get _base => AppConfig.apiBaseUrl;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Pref keys
  static const _kAskedOnce = 'push.permission.askedOnce';
  static const _kDeniedUntilSettings = 'push.permission.deniedUntilSettings';
  static const _kLastToken = 'push.lastRegisteredFcmToken';

  /// ---- BACKGROUND HANDLER (fixes duplicate isolate) ------------------------
  /// Call exactly once on cold start (before runApp).
  static Future<void> registerBackgroundHandler() async {
    if (_bgRegistered) return;
    _bgRegistered = true;
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// Foreground listeners / presentation options (safe to call multiple times).
  Future<void> initForegroundHandlers() async {
    if (Platform.isIOS) {
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      // Keep light; you can surface a snackbar/toast here if desired.
      debugPrint('🔔 FCM foreground: ${m.messageId}');
    });
  }

  /// Ask for push permission politely.
  ///
  /// - `showRationale` should display your explanation dialog and return true to proceed.
  /// - We remember "denied" and won't nag again unless `forceAsk: true`.
  Future<bool> ensurePermission({
    required BuildContext context,
    required Future<bool> Function(BuildContext ctx) showRationale,
    bool forceAsk = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Don’t nag if previously denied (unless forced via a Settings toggle)
    final denied = prefs.getBool(_kDeniedUntilSettings) ?? false;
    if (denied && !forceAsk) return false;

    // Only show your rationale once (unless forced)
    final askedOnce = prefs.getBool(_kAskedOnce) ?? false;
    if (!askedOnce || forceAsk) {
      final proceed = await showRationale(context);
      if (!proceed) return false;
      await prefs.setBool(_kAskedOnce, true);
    }

    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');
    final ok =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    await prefs.setBool(_kDeniedUntilSettings, !ok);

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are off. You can enable them in Settings.',
          ),
        ),
      );
    }
    return ok;
  }

  /// Fetch device token and register with backend if changed.
  /// Safe to call after ensurePermission==true (or anytime; it no-ops without a token).
  Future<bool> syncToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      debugPrint('🔑 FCM token: $token');

      if (token == null || token.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_kLastToken);

      if (last == token) {
        // Already registered this token — skip network
        return true;
      }

      await registerToken(userId: userId, token: token);
      await prefs.setString(_kLastToken, token);
      return true;
    } catch (e) {
      debugPrint('⚠️ syncToken failed: $e');
      return false;
    }
  }

  /// Disable push for this device:
  /// - Deletes the FCM token so backend can’t target it.
  /// - Clears last registered token cache.
  /// - Optionally unregisters on your server (best-effort).
  Future<void> disable({String? userId}) async {
    try {
      if (userId != null) {
        // Best-effort server unregister. Ignore failures.
        await unregisterToken(userId: userId);
      }
    } catch (_) {}

    try {
      await _fcm.deleteToken();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastToken);
  }

  // --------------------------------------------------------------------------
  // Your existing backend calls (kept identical to avoid breaking callers)
  // --------------------------------------------------------------------------

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

/// Top-level background handler (must be a top-level/entry-point).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep this minimal; heavy work can be scheduled.
  debugPrint('🔕 FCM (background): ${message.messageId}');
}
