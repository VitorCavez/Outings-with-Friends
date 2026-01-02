// lib/providers/contacts_provider.dart
import 'package:flutter/foundation.dart';
import '../services/contacts_service.dart';

class ContactsProvider extends ChangeNotifier {
  ContactsProvider({required this.service});

  final ContactsService service;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _contacts = [];

  bool get loading => _loading;
  String? get error => _error;
  List<Map<String, dynamic>> get contacts => List.unmodifiable(_contacts);

  /// Load my contacts list
  Future<void> refresh() async {
    _setLoading(true);
    _setError(null);
    try {
      _contacts = await service.listContacts();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Returns:
  /// - a user map if found
  /// - null if not found (404)
  /// Sets provider error only on *real* errors (network/server/auth).
  Future<Map<String, dynamic>?> lookupByPhone(
    String phone, {
    String defaultCountryCode = '+353',
  }) async {
    _setError(null);
    try {
      final user = await service.lookupByPhone(
        phone,
        defaultCountryCode: defaultCountryCode,
      );
      // user == null means "not found" — not an app error
      return user;
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  /// Add contact by phone.
  ///
  /// Returns true if the contact was added (or already existed).
  /// Returns false if it failed (error will be set).
  Future<bool> addByPhone(
    String phone, {
    String? label,
    String defaultCountryCode = '+353',
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      // Optional improvement: try lookup first so we can show "not found"
      // before attempting to create the contact.
      final found = await service.lookupByPhone(
        phone,
        defaultCountryCode: defaultCountryCode,
      );

      if (found == null) {
        _setError('No user found with that phone number.');
        return false;
      }

      await service.addContactByPhone(
        phone,
        label: label,
        defaultCountryCode: defaultCountryCode,
      );

      // Refresh list without re-toggling loading inside refresh()
      _contacts = await service.listContacts();
      notifyListeners();

      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> remove(String userId) async {
    _setLoading(true);
    _setError(null);
    try {
      await service.removeContact(userId);
      _contacts.removeWhere((c) => (c['user']?['id'] ?? '') == userId);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _setError(String? v) {
    _error = v;
    notifyListeners();
  }
}
