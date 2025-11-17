import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // We navigate using this key's context (provided by AppRouter).
  GlobalKey<NavigatorState>? _navKey;
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navKey = key;
  }

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (resp) {
        _handleTap(resp.payload);
      },
      onDidReceiveBackgroundNotificationResponse: _backgroundTapHandler,
    );

    if (!kIsWeb) {
      // Android 13+ runtime permission
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  // ---- Public API -----------------------------------------------------------

  Future<void> showDm({
    required String peerUserId,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'dm_messages',
      'Direct Messages',
      channelDescription: 'Incoming direct messages',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // id
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'dm:$peerUserId',
    );
  }

  // ---- Internal helpers -----------------------------------------------------

  void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;

    if (payload.startsWith('dm:')) {
      final peer = payload.substring(3);
      // Jump into the Messages tab root first, then to that chat route.
      // With GoRouter you can go directly to the nested path:
      GoRouter.of(ctx).go('/messages/chat/$peer');
    }
  }
}

// Note: iOS can deliver background tap here; keep it top-level.
@pragma('vm:entry-point')
void _backgroundTapHandler(NotificationResponse resp) {
  // In a full app you might cache the payload and process it on next launch.
  // For simplicity we rely on foreground onDidReceive... above.
}
