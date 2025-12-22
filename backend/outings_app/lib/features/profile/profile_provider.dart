// lib/features/profile/profile_provider.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores a per-user "local profile":
/// - display name (override of backend fullName)
/// - avatarPath (local file path on device)
///
/// Data is keyed by the current auth userId so that:
/// - User A and User B on the same device have independent names/avatars.
/// - On logout we can reset to a safe default.
class ProfileProvider extends ChangeNotifier {
  static const String _fallbackName = 'You';

  String? _userId; // current auth user
  String _displayName = _fallbackName;
  String? _avatarPath;

  String? get userId => _userId;
  String get displayName => _displayName;
  String? get avatarPath => _avatarPath;

  /// Build per-user keys so multiple accounts on the same device
  /// don't overwrite one another.
  String _nameKey(String uid) => 'profile_name_$uid';
  String _avatarKey(String uid) => 'profile_avatar_path_$uid';

  /// Load profile data for the given userId.
  ///
  /// Called from main.dart whenever AuthProvider.currentUserId changes.
  Future<void> loadForUser(String? userId) async {
    // If nothing changed, avoid extra work / notifyListeners.
    if (_userId == userId) return;

    _userId = userId;

    if (userId == null || userId.isEmpty) {
      // Logged out → show safe defaults.
      _displayName = _fallbackName;
      _avatarPath = null;
      notifyListeners();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _displayName = prefs.getString(_nameKey(userId)) ?? _fallbackName;
      _avatarPath = prefs.getString(_avatarKey(userId));
    } catch (e) {
      debugPrint('⚠️ ProfileProvider.loadForUser error: $e');
      _displayName = _fallbackName;
      _avatarPath = null;
    }

    notifyListeners();
  }

  /// Update display name for the current user and persist it.
  Future<void> setDisplayName(String name) async {
    final uid = _userId;
    _displayName = name.trim().isEmpty ? _fallbackName : name.trim();

    if (uid != null && uid.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_nameKey(uid), _displayName);
      } catch (e) {
        debugPrint('⚠️ ProfileProvider.setDisplayName error: $e');
      }
    }

    notifyListeners();
  }

  /// Update avatar path for the current user and persist it.
  Future<void> setAvatarPath(String? path) async {
    final uid = _userId;
    _avatarPath = (path == null || path.isEmpty) ? null : path;

    if (uid != null && uid.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_avatarPath == null) {
          await prefs.remove(_avatarKey(uid));
        } else {
          await prefs.setString(_avatarKey(uid), _avatarPath!);
        }
      } catch (e) {
        debugPrint('⚠️ ProfileProvider.setAvatarPath error: $e');
      }
    }

    notifyListeners();
  }

  /// ImageProvider used by avatars.
  ImageProvider? avatarImageProvider() {
    if (_avatarPath == null) return null;
    try {
      return FileImage(File(_avatarPath!));
    } catch (_) {
      return null;
    }
  }

  /// Clear in-memory state (used on logout). We intentionally do NOT
  /// delete all SharedPreferences keys here, so if the same user logs
  /// in again later, `loadForUser(userId)` can restore their data.
  Future<void> reset() async {
    _userId = null;
    _displayName = _fallbackName;
    _avatarPath = null;
    notifyListeners();
  }
}
