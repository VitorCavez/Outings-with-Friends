// lib/features/auth/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // BuildContext
import 'package:go_router/go_router.dart'; // <- use go_router to exit shell
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_api.dart';

class AuthProvider extends ChangeNotifier {
  static const _kTokenKey = 'auth_token';
  static const _kUserIdKey = 'auth_user_id';

  String? _token;
  String? _currentUserId;

  // Primary getters
  String? get token => _token;
  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  // Alias used by various parts of the app (router, services)
  String? get authToken => _token;

  /// Restore session once during app startup.
  Future<void> loadFromStorage() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _token = sp.getString(_kTokenKey);
      _currentUserId = sp.getString(_kUserIdKey);
      debugPrint(
        '🔁 loadFromStorage: tokenLen=${_token?.length ?? 0}, uid=$_currentUserId',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ loadFromStorage error: $e');
    }
  }

  Future<void> _applyAuthResult(AuthResult result) async {
    _token = result.token;
    _currentUserId = result.userId;
    debugPrint(
      '🔐 AuthProvider.applyAuthResult: tokenLen=${_token?.length ?? 0}, uid=$_currentUserId',
    );

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kTokenKey, _token!);
      await sp.setString(_kUserIdKey, _currentUserId!);
      debugPrint(
        '💾 AuthProvider.persisted: tokenLen=${_token!.length}, uid=$_currentUserId',
      );
    } catch (e) {
      debugPrint('⚠️ persist token error: $e');
    }

    notifyListeners();
  }

  /// Login using API and persist token/userId.
  Future<void> login(String email, String password) async {
    final api = AuthApi();
    final result = await api.login(email: email, password: password);
    await _applyAuthResult(result);
  }

  /// Register using API and persist token/userId (so the user is logged in
  /// immediately after registering).
  Future<void> register(String fullName, String email, String password) async {
    final api = AuthApi();
    final result = await api.register(
      fullName: fullName,
      email: email,
      password: password,
    );
    await _applyAuthResult(result);
  }

  /// Clears in-memory + persisted auth state.
  Future<void> logout() async {
    debugPrint('🚪 logout(): clearing token + userId…');
    _token = null;
    _currentUserId = null;

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kTokenKey);
      await sp.remove(_kUserIdKey);
      debugPrint(
        '✅ after remove: token=${sp.getString(_kTokenKey)}, uid=${sp.getString(_kUserIdKey)}',
      );
    } catch (e) {
      debugPrint('⚠️ clear token error: $e');
    }

    notifyListeners();
  }

  /// Convenience: logout + route to /login (works from any tab/shell).
  Future<void> signOut(BuildContext context) async {
    try {
      await logout();
    } finally {
      // Leave the shell and land on the login route.
      // This avoids residual back stack issues across branches.
      try {
        context.go('/login');
      } catch (_) {
        // Fallback in the unlikely event context is stale.
        GoRouter.of(context).go('/login');
      }
    }
  }
}
