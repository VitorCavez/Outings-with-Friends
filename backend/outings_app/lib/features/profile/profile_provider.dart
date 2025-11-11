// lib/features/profile/profile_provider.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileProvider extends ChangeNotifier {
  static const _kNameKey = 'profile_name';
  static const _kAvatarPathKey = 'profile_avatar_path';

  String _displayName = 'You';
  String? _avatarPath;

  String get displayName => _displayName;
  String? get avatarPath => _avatarPath;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_kNameKey) ?? _displayName;
    _avatarPath = prefs.getString(_kAvatarPathKey);
    notifyListeners();
  }

  Future<void> setDisplayName(String name) async {
    _displayName = name.trim().isEmpty ? 'You' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNameKey, _displayName);
    notifyListeners();
  }

  Future<void> setAvatarPath(String? path) async {
    _avatarPath = (path == null || path.isEmpty) ? null : path;
    final prefs = await SharedPreferences.getInstance();
    if (_avatarPath == null) {
      await prefs.remove(_kAvatarPathKey);
    } else {
      await prefs.setString(_kAvatarPathKey, _avatarPath!);
    }
    notifyListeners();
  }

  ImageProvider? avatarImageProvider() {
    if (_avatarPath == null) return null;
    try {
      return FileImage(File(_avatarPath!));
    } catch (_) {
      return null;
    }
  }
}
