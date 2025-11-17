// lib/features/contacts/display_name.dart
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../providers/contacts_provider.dart';

/// Simple resolver that maps a userId to a friendly display name using
/// the in-memory contacts loaded by ContactsProvider.
class DisplayNameResolver {
  DisplayNameResolver(this._contacts);

  final List<Map<String, dynamic>> _contacts;

  /// Returns the best display label for a given [userId].
  /// Fallbacks to a short id tail if the name isn't known yet.
  String forUserId(String userId, {String? fallback}) {
    if (userId.isEmpty) return fallback ?? 'Unknown';
    final match = _contacts.firstWhere(
      (c) => (c['user']?['id'] ?? '') == userId,
      orElse: () => const {},
    );
    final name = (match['user']?['fullName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    // fallback: last 4 of id (or provided fallback)
    final shortId = userId.length > 8
        ? userId.substring(userId.length - 4)
        : userId;
    return fallback ?? shortId;
  }

  /// Quick helper to build initials for chips/avatars (optional).
  String initialsFor(String userId) {
    final name = forUserId(userId);
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '🙂';
    if (parts.length == 1)
      return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.first.toString() +
            parts.last.characters.first.toString())
        .toUpperCase();
  }

  /// Convenience getter from the widget tree.
  static DisplayNameResolver of(BuildContext context) {
    final contacts = context.watch<ContactsProvider>().contacts;
    return DisplayNameResolver(contacts);
  }
}
