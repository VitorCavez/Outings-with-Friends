// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// App
import 'routes/app_router.dart';
import 'features/auth/auth_provider.dart';
import 'services/push_service.dart';

// 🚀 Offline Outbox
import 'services/outbox_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bool useFirebase = Platform.isAndroid || Platform.isIOS;

  if (useFirebase) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // ✅ Start Offline Outbox (connectivity listener + auto-flush)
  OutboxService.instance.start();

  runApp(OutingsApp(useFirebase: useFirebase));
}

class OutingsApp extends StatelessWidget {
  const OutingsApp({super.key, required this.useFirebase});
  final bool useFirebase;

  @override
  Widget build(BuildContext context) {
    final appShell = MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: AppRouter.router,
      title: 'Outings with Friends',
      theme: ThemeData(primarySwatch: Colors.purple),
    );

    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: Builder(
        builder: (ctx) {
          // 🔧 CHECKLIST EXECUTOR: wire token-based HTTP executor
          OutboxService.instance.setChecklistExecutor(
            OutboxService.buildHttpChecklistExecutor(
              tokenProvider: () async {
                // TODO: read your JWT from AuthProvider once auth is ready
                // final auth = ctx.read<AuthProvider>();
                // return auth.token ?? '';
                return '';
              },
            ),
          );
          return useFirebase ? FCMInitializer(child: appShell) : appShell;
        },
      ),
    );
  }
}

class FCMInitializer extends StatefulWidget {
  const FCMInitializer({super.key, required this.child});
  final Widget child;

  @override
  State<FCMInitializer> createState() => _FCMInitializerState();
}

class _FCMInitializerState extends State<FCMInitializer> {
  StreamSubscription<String>? _tokenSub;
  static const String _fallbackUserId = '698381fc-ad46-49b0-94c5-3f6c94534bc9';

  @override
  void initState() {
    super.initState();
    _initFCM();
  }

  Future<void> _initFCM() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

      FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        debugPrint('📩 FCM (foreground): ${m.notification?.title} - ${m.notification?.body}');
      });

      await _registerCurrentToken();

      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 FCM token refreshed: $newToken');
        final userId = _resolveUserId();
        if (userId != null) {
          await PushService.registerToken(userId: userId, token: newToken);
        }
      });
    } catch (e) {
      debugPrint('⚠️ FCM init skipped/failed: $e');
    }
  }

  String? _resolveUserId() {
    final auth = context.read<AuthProvider>();
    try {
      return _fallbackUserId; // replace once auth is ready
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
