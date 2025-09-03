import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const MainNavigation(),
      ),
      GoRoute(
        path: '/discover',
        builder: (context, state) => const DiscoverScreen(),
      ),

      // 1-on-1 chat: /chat/<peerId>
      GoRoute(
        path: '/chat/:peerId',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          final currentUserId = auth.currentUserId;
          if (currentUserId == null) {
            // not logged in → show login
            return const LoginScreen();
          }

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

      // Group chat: /group/<groupId>
      GoRoute(
        path: '/group/:groupId',
        builder: (context, state) {
          final auth = context.read<AuthProvider>();
          final currentUserId = auth.currentUserId;
          if (currentUserId == null) {
            return const LoginScreen();
          }

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

      GoRoute(
        path: '/messages',
        builder: (context, state) => const MessagesScreen(),
      ),
    ],
  );
}
