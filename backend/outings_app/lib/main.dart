// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Theme
import 'theme/app_theme.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// App
import 'routes/app_router.dart';
import 'features/auth/auth_provider.dart';
import 'services/push_service.dart';

// 🚀 Offline Outbox
import 'services/outbox_service.dart';

// 🌐 Deep Links
import 'deeplink/deeplink_handler.dart';

// 👤 Profile (local name + avatar)
import 'features/profile/profile_provider.dart';

// 🔌 Global socket + caching
import 'services/socket_service.dart';
import 'features/messages/messages_repository.dart';
import 'models/message.dart';

// 🧭 Contacts
import 'providers/contacts_provider.dart';
import 'services/contacts_service.dart';
import 'config/app_config.dart';

// 🔔 Local notifications (tap -> navigate)
import 'services/notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bool useFirebase = Platform.isAndroid || Platform.isIOS;

  if (useFirebase) {
    await Firebase.initializeApp();
    // ✅ Use our PushService top-level bg handler (prevents duplicate isolate warnings)
    await PushService.registerBackgroundHandler();
  }

  // ✅ Start Offline Outbox (connectivity listener + auto-flush)
  OutboxService.instance.start();

  // ✅ Wire notifications → GoRouter via the root navigator key
  NotificationsService.instance.setNavigatorKey(AppRouter.rootNavigatorKey);
  await NotificationsService.instance.init();

  runApp(OutingsApp(useFirebase: useFirebase));
}

class OutingsApp extends StatelessWidget {
  const OutingsApp({super.key, required this.useFirebase});
  final bool useFirebase;

  @override
  Widget build(BuildContext context) {
    // Router shell using our app theme + global gradient background
    final appShell = MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: AppRouter.router,
      title: 'Outings with Friends',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final gradient = isDark
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0E0E12), Color(0xFF0B0B10)],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFAFAFF)],
              );

        final transparentScaffoldTheme = Theme.of(
          context,
        ).copyWith(scaffoldBackgroundColor: Colors.transparent);

        return DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: Theme(
            data: transparentScaffoldTheme,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );

    return MultiProvider(
      providers: [
        // 🔑 Auth: load saved token/userId on startup
        ChangeNotifierProvider(
          create: (_) => AuthProvider()..loadFromStorage(),
        ),

        // 👤 Profile: depends on Auth so each user gets their own local profile.
        //
        // When auth.currentUserId changes (login / logout / switch),
        // we call profile.loadForUser(userId) to load that user's
        // saved name + avatar (or reset to defaults when logged out).
        ChangeNotifierProxyProvider<AuthProvider, ProfileProvider>(
          create: (_) => ProfileProvider(),
          update: (context, auth, previous) {
            final profile = previous ?? ProfileProvider();
            // Fire-and-forget; provider internally avoids redundant reloads.
            profile.loadForUser(auth.currentUserId);
            return profile;
          },
        ),

        /// 📇 ContactsProvider depends on Auth (for JWT) and base URL (host w/o /api).
        ChangeNotifierProxyProvider<AuthProvider, ContactsProvider>(
          create: (_) => ContactsProvider(
            service: ContactsService(
              baseUrl: AppConfig.socketBaseUrl, // host only (no /api)
              token: '', // filled in update()
            ),
          ),
          update: (context, auth, previous) {
            final dyn = auth as dynamic;
            final token = (dyn.authToken ?? dyn.token) as String? ?? '';

            MessagesRepository.setAuthToken(token.isNotEmpty ? token : null);

            final service = ContactsService(
              baseUrl:
                  AppConfig.socketBaseUrl, // host root; service appends /api
              token: token,
            );

            final prov = ContactsProvider(service: service);
            if (token.isNotEmpty) {
              prov.refresh(); // fire-and-forget
            }
            return prov;
          },
        ),
      ],
      child: Builder(
        builder: (ctx) {
          Future<String> tokenProvider() async {
            try {
              final auth = ctx.read<AuthProvider>();
              final dyn = auth as dynamic;
              final token = (dyn.authToken ?? dyn.token) as String?;
              return token ?? '';
            } catch (_) {
              return '';
            }
          }

          OutboxService.instance.setChecklistExecutor(
            OutboxService.buildHttpChecklistExecutor(
              tokenProvider: tokenProvider,
            ),
          );
          OutboxService.instance.setOutingCreateExecutor(
            OutboxService.buildHttpOutingCreateExecutor(
              tokenProvider: tokenProvider,
            ),
          );
          OutboxService.instance.setOutingUpdateExecutor(
            OutboxService.buildHttpOutingUpdateExecutor(
              tokenProvider: tokenProvider,
            ),
          );

          final withFcm = useFirebase
              ? FCMInitializer(child: appShell)
              : appShell;

          return SocketBootstrap(child: DeepLinkInitializer(child: withFcm));
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
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-run when auth changes (e.g., user logs in)
    _bootstrapOnce();
  }

  Future<void> _bootstrapOnce() async {
    if (_didInit) return;
    _didInit = true;

    // 🚧 Completely guard push until ready/toggled
    if (!AppConfig.pushEnabled) {
      debugPrint('🔕 Push disabled by AppConfig.pushEnabled.');
      return;
    }

    // Set basic foreground handlers (presentation on iOS, onMessage logging)
    await PushService.I.initForegroundHandlers();

    // Ask permission with a small rationale the first time.
    final allowed = await PushService.I.ensurePermission(
      context: context,
      showRationale: (ctx) async {
        return await showDialog<bool>(
              context: ctx,
              builder: (_) => AlertDialog(
                title: const Text('Enable notifications?'),
                content: const Text(
                  'We’ll only notify you about invites, replies, and reminders—no spam.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Allow'),
                  ),
                ],
              ),
            ) ??
            false;
      },
    );

    if (allowed) {
      final userId = _currentUserId();
      if (userId != null) {
        await PushService.I.syncToken(userId);
      }

      // Keep server in sync on token refresh
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((
        newToken,
      ) async {
        debugPrint('🔄 FCM token refreshed: $newToken');
        final uid = _currentUserId();
        if (uid != null) {
          // syncToken will skip if same; still good to call to ensure backend registration
          await PushService.I.syncToken(uid);
        }
      });
    }
  }

  String? _currentUserId() {
    final auth = context.read<AuthProvider?>();
    return auth?.currentUserId;
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }
}

/// Wraps the app to start/stop deep-link listening (no-op on web/desktop).
class DeepLinkInitializer extends StatefulWidget {
  const DeepLinkInitializer({super.key, required this.child});
  final Widget child;

  @override
  State<DeepLinkInitializer> createState() => _DeepLinkInitializerState();
}

class _DeepLinkInitializerState extends State<DeepLinkInitializer> {
  final _handler = DeepLinkHandler();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handler.start(context);
    });
  }

  @override
  void dispose() {
    _handler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Initializes a single SocketService once the user is logged in and
/// caches incoming messages to the in-memory repository.
class SocketBootstrap extends StatefulWidget {
  const SocketBootstrap({super.key, required this.child});
  final Widget child;

  @override
  State<SocketBootstrap> createState() => _SocketBootstrapState();
}

class _SocketBootstrapState extends State<SocketBootstrap> {
  final _socket = SocketService();
  final _repo = MessagesRepository();
  StreamSubscription<bool>? _connSub;
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureSocketBound();
  }

  void _ensureSocketBound() {
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUserId;
    final hasToken = auth.isLoggedIn;

    if (!hasToken || userId == null || userId.isEmpty) {
      if (_attached) {
        try {
          _socket.off('receive_message');
          _socket.disconnect();
        } catch (_) {}
        _attached = false;
      }
      return;
    }

    if (_attached) return;

    _socket.initSocket(userId: userId);

    _socket.on('receive_message', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final msg = Message.fromMap(map, userId);

        if (msg.groupId == null) {
          final String peer = msg.isMine
              ? (msg.recipientId ?? '')
              : msg.senderId;
          if (peer.isNotEmpty) {
            _repo.upsertOne(peer, msg);

            final viewing = _repo.activePeer.value == peer;
            if (!msg.isMine && !viewing) {
              NotificationsService.instance.showDm(
                peerUserId: peer,
                title: 'New message',
                body: msg.text.isEmpty ? '(attachment)' : msg.text,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('socket receive parse error: $e');
      }
    });

    _attached = true;
  }

  @override
  void dispose() {
    try {
      _socket.off('receive_message');
      _connSub?.cancel();
      _socket.disconnect();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
