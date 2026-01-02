// lib/features/profile/profile_provider.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores a per-user "local profile":
/// - display name (override of backend fullName)
/// - avatarPath (local file path on device)
/// - avatarUrl  (remote URL, e.g. from /api/uploads -> Cloudinary)
///
/// Data is keyed by the current auth userId so that:
/// - User A and User B on the same device have independent names/avatars.
/// - On logout we can reset to a safe default.
class ProfileProvider extends ChangeNotifier {
  static const String _fallbackName = 'You';

  String? _userId; // current auth user
  String _displayName = _fallbackName;

  // Local file path (highest priority for display)
  String? _avatarPath;

  // Remote URL (fallback if no local file)
  String? _avatarUrl;

  String? get userId => _userId;
  String get displayName => _displayName;
  String? get avatarPath => _avatarPath;
  String? get avatarUrl => _avatarUrl;

  /// Build per-user keys so multiple accounts on the same device
  /// don't overwrite one another.
  String _nameKey(String uid) => 'profile_name_$uid';
  String _avatarPathKey(String uid) => 'profile_avatar_path_$uid';
  String _avatarUrlKey(String uid) => 'profile_avatar_url_$uid';

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
      _avatarUrl = null;
      notifyListeners();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _displayName = prefs.getString(_nameKey(userId)) ?? _fallbackName;
      _avatarPath = prefs.getString(_avatarPathKey(userId));
      _avatarUrl = prefs.getString(_avatarUrlKey(userId));
    } catch (e) {
      debugPrint('⚠️ ProfileProvider.loadForUser error: $e');
      _displayName = _fallbackName;
      _avatarPath = null;
      _avatarUrl = null;
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
  ///
  /// This sets the LOCAL avatar file path. We do NOT automatically clear the URL.
  /// (You might still want the URL fallback if the local file is deleted.)
  Future<void> setAvatarPath(String? path) async {
    final uid = _userId;
    _avatarPath = (path == null || path.isEmpty) ? null : path;

    if (uid != null && uid.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_avatarPath == null) {
          await prefs.remove(_avatarPathKey(uid));
        } else {
          await prefs.setString(_avatarPathKey(uid), _avatarPath!);
        }
      } catch (e) {
        debugPrint('⚠️ ProfileProvider.setAvatarPath error: $e');
      }
    }

    notifyListeners();
  }

  /// Update avatar URL for the current user and persist it.
  ///
  /// This is the REMOTE avatar URL (e.g. Cloudinary). Used when no local file exists.
  Future<void> setAvatarUrl(String? url) async {
    final uid = _userId;
    final next = (url == null || url.trim().isEmpty) ? null : url.trim();
    _avatarUrl = next;

    if (uid != null && uid.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_avatarUrl == null) {
          await prefs.remove(_avatarUrlKey(uid));
        } else {
          await prefs.setString(_avatarUrlKey(uid), _avatarUrl!);
        }
      } catch (e) {
        debugPrint('⚠️ ProfileProvider.setAvatarUrl error: $e');
      }
    }

    notifyListeners();
  }

  /// ImageProvider used by avatars.
  ///
  /// Priority:
  /// 1) local file path (fastest, works offline)
  /// 2) remote URL (shows profile image after restart / other screens)
  ImageProvider? avatarImageProvider() {
    // 1) Local file
    if (_avatarPath != null) {
      try {
        final f = File(_avatarPath!);
        if (f.existsSync()) return FileImage(f);
      } catch (_) {
        // ignore and fall back to url
      }
    }

    // 2) Remote url
    final url = _avatarUrl;
    if (url != null && url.isNotEmpty) {
      try {
        return NetworkImage(url);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// Clear in-memory state (used on logout). We intentionally do NOT
  /// delete all SharedPreferences keys here, so if the same user logs
  /// in again later, `loadForUser(userId)` can restore their data.
  Future<void> reset() async {
    _userId = null;
    _displayName = _fallbackName;
    _avatarPath = null;
    _avatarUrl = null;
    notifyListeners();
  }
}
