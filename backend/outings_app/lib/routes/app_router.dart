// lib/routes/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Screens
import '../screens/splash_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../screens/home_screen.dart';
import '../features/discover/discover_screen.dart';
import '../screens/main_navigation.dart';
import '../features/messages/chat_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/messages/chat_state.dart';
import '../features/auth/auth_provider.dart';
import '../features/groups/groups_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/outings/outing_details_screen.dart';
import '../features/outings/outings_list_screen.dart';

// ✅ Plan & Profile (public profile page you already have)
import '../features/plan/plan_screen.dart';
import '../features/plan/create_outing_screen.dart';
import '../features/profile/pages/profile_page.dart';

// 👤 New: personal profile & settings
import '../features/profile/my_profile_page.dart';
import '../features/settings/settings_page.dart';

import '../services/api_client.dart';
import '../config/app_config.dart';

// ✅ NEW: Contacts service/state for Messages → Contacts tab
import '../services/contacts_service.dart';
import '../providers/contacts_provider.dart';

class AppRouter {
  static ApiClient _buildApiClient(BuildContext context) {
    String? token;
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      token = (dyn.authToken ?? dyn.token) as String?;
    } catch (_) {}
    final baseUrl = AppConfig.apiBaseUrl;
    return ApiClient(baseUrl: baseUrl, authToken: token);
  }

  static String _readJwt(BuildContext context) {
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      final token = (dyn.authToken ?? dyn.token) as String?;
      return token ?? '';
    } catch (_) {
      return '';
    }
  }

  // ---- Navigator keys (root + per-branch) ----------------------------------
  static final _rootKey = GlobalKey<NavigatorState>();
  static final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  static final _discoverKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
  static final _planKey = GlobalKey<NavigatorState>(debugLabel: 'plan');
  static final _groupsKey = GlobalKey<NavigatorState>(debugLabel: 'groups');
  static final _calendarKey = GlobalKey<NavigatorState>(debugLabel: 'calendar');
  static final _messagesKey = GlobalKey<NavigatorState>(debugLabel: 'messages');

  /// Expose the root navigator key so services can navigate without context.
  static GlobalKey<NavigatorState> get rootNavigatorKey => _rootKey;

  static final router = GoRouter(
    initialLocation: '/', // Splash first
    navigatorKey: _rootKey,
    routes: [
      // Outside the shell: splash & auth only
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // Quick list entry (convenient from dev panel)
      GoRoute(
        path: '/my-outings',
        builder: (_, __) => const OutingsListScreen(),
      ),

      // Global deep-link: keep it in Plan branch
      GoRoute(
        path: '/outings/:id',
        redirect: (_, state) => '/plan/outings/${state.pathParameters['id']}',
      ),

      GoRoute(
        path: '/profile',
        redirect: (ctx, state) {
          final uid = ctx.read<AuthProvider?>()?.currentUserId;
          return (uid == null) ? '/login' : '/plan/profile/$uid';
        },
      ),
      GoRoute(
        path: '/profile/:id',
        redirect: (ctx, state) => '/plan/profile/${state.pathParameters['id']}',
      ),

      // Persistent bottom bar shell with 6 branches (Home + Discover + Plan + Groups + Calendar + Messages)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigation(
            navigationShell: navigationShell,
            currentLocation: state.uri.toString(),
          );
        },
        branches: [
          // 0) HOME
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (_, __) => const MyProfilePage(),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (_, __) => const SettingsPage(),
                  ),
                ],
              ),
            ],
          ),

          // 1) DISCOVER
          StatefulShellBranch(
            navigatorKey: _discoverKey,
            routes: [
              GoRoute(
                path: '/discover',
                builder: (_, __) => const DiscoverScreen(),
                routes: [
                  GoRoute(
                    path: 'outings/:id',
                    builder: (context, state) {
                      final outingId = state.pathParameters['id']!;
                      return OutingDetailsScreen(outingId: outingId);
                    },
                  ),
                ],
              ),
            ],
          ),

          // 2) PLAN
          StatefulShellBranch(
            navigatorKey: _planKey,
            routes: [
              GoRoute(
                path: '/plan',
                builder: (_, __) => const PlanScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (_, __) => const CreateOutingScreen(),
                  ),
                  GoRoute(
                    path: 'outings/:id',
                    builder: (context, state) {
                      final outingId = state.pathParameters['id']!;
                      return OutingDetailsScreen(outingId: outingId);
                    },
                  ),
                  // Public profile (by userId)
                  GoRoute(
                    path: 'profile/:userId',
                    builder: (context, state) {
                      final userId = state.pathParameters['userId']!;
                      final api = _buildApiClient(context);
                      return ProfilePage(userId: userId, api: api);
                    },
                  ),
                ],
              ),
            ],
          ),

          // 3) GROUPS
          StatefulShellBranch(
            navigatorKey: _groupsKey,
            routes: [
              GoRoute(
                path: '/groups',
                builder: (_, __) => const GroupsScreen(),
              ),
            ],
          ),

          // 4) CALENDAR
          StatefulShellBranch(
            navigatorKey: _calendarKey,
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, __) => const CalendarScreen(),
              ),
            ],
          ),

          // 5) MESSAGES
          StatefulShellBranch(
            navigatorKey: _messagesKey,
            routes: [
              GoRoute(
                path: '/messages',
                builder: (context, __) {
                  final token = _readJwt(context);
                  return ChangeNotifierProvider(
                    create: (_) => ContactsProvider(
                      service: ContactsService(
                        baseUrl: AppConfig.apiBaseUrl,
                        token: token,
                      ),
                    ),
                    child: const MessagesScreen(),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'chat/:peerId',
                    builder: (context, state) {
                      final auth = context.read<AuthProvider>();
                      final currentUserId = auth.currentUserId;
                      if (currentUserId == null) return const LoginScreen();
                      final peerId = state.pathParameters['peerId']!;
                      return ChangeNotifierProvider(
                        create: (_) => ChatState(
                          currentUserId: currentUserId,
                          peerUserId: peerId,
                        ),
                        child: const ChatScreen(),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'group/:groupId',
                    builder: (context, state) {
                      final auth = context.read<AuthProvider>();
                      final currentUserId = auth.currentUserId;
                      if (currentUserId == null) return const LoginScreen();
                      final groupId = state.pathParameters['groupId']!;
                      return ChangeNotifierProvider(
                        create: (_) => ChatState(
                          currentUserId: currentUserId,
                          groupId: groupId,
                        ),
                        child: const ChatScreen(),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
