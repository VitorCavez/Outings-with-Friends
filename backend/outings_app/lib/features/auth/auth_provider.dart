import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  String? _currentUserId;

  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _currentUserId != null;

  // Call this after successful login (set the real user id returned by backend)
  void signIn(String userId) {
    _currentUserId = userId;
    notifyListeners();
  }

  // Call this on logout
  void signOut() {
    _currentUserId = null;
    notifyListeners();
  }
}
