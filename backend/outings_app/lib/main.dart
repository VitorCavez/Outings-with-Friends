// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// App
import 'routes/app_router.dart';
import 'features/auth/auth_provider.dart';
import 'services/push_service.dart';

/// Background FCM handler must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Do any lightweight background handling here (logging, local storage, etc.)
  // Avoid UI here.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase once.
  await Firebase.initializeApp();

  // Register the background handler early.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const OutingsApp());
}

class OutingsApp extends StatelessWidget {
  const OutingsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: FCMInitializer(
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: AppRouter.router,
          title: 'Outings with Friends',
          theme: ThemeData(
            primarySwatch: Colors.purple,
          ),
        ),
      ),
    );
  }
}

/// A small widget that sets up Firebase Messaging once the widget tree is ready.
/// It:
/// - requests notification permission (Android 13+ and iOS)
/// - fetches the FCM token and registers it with your backend
/// - listens for token refresh and re-registers
/// - (optionally) logs foreground messages
class FCMInitializer extends StatefulWidget {
  const FCMInitializer({super.key, required this.child});
  final Widget child;

  @override
  State<FCMInitializer> createState() => _FCMInitializerState();
}

class _FCMInitializerState extends State<FCMInitializer> {
  StreamSubscription<String>? _tokenSub;

  // TODO: Replace this with your real logged-in user id from AuthProvider once available.
  // For now we keep the same placeholder you've been using during Phase 3.
  static const String _fallbackUserId = '698381fc-ad46-49b0-94c5-3f6c94534bc9';

  @override
  void initState() {
    super.initState();
    _initFCM();
  }

  Future<void> _initFCM() async {
    // Ask for permission (iOS required, Android 13+ will show prompt)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

    // Log foreground messages (optional; for dev)
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      debugPrint('📩 FCM (foreground): ${m.notification?.title} - ${m.notification?.body}');
    });

    // Get the initial token and register it
    await _registerCurrentToken();

    // Keep backend updated when the token rotates
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('🔄 FCM token refreshed: $newToken');
      final userId = _resolveUserId();
      if (userId != null) {
        await PushService.registerToken(userId: userId, token: newToken);
      }
    });
  }

  String? _resolveUserId() {
    // Try to get a real user id from AuthProvider if it’s available.
    // Adjust this to match your AuthProvider’s API when you wire auth.
    final auth = context.read<AuthProvider>();
    try {
      // Common patterns — adapt as needed:
      // return auth.currentUser?.id;
      // return auth.userId;
      // For now use the known fallback (replace when auth is ready):
      return _fallbackUserId;
    } catch (_) {
      return _fallbackUserId;
    }
  }

  Future<void> _registerCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('🔑 FCM token: $token');
    if (token == null) return;

    final userId = _resolveUserId();
    if (userId != null) {
      try {
        await PushService.registerToken(userId: userId, token: token);
      } catch (e) {
        debugPrint('⚠️ registerToken failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
