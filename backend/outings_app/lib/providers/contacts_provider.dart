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

  Future<Map<String, dynamic>?> lookupByPhone(
    String phone, {
    String defaultCountryCode = '+353',
  }) async {
    try {
      return await service.lookupByPhone(
        phone,
        defaultCountryCode: defaultCountryCode,
      );
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  Future<void> addByPhone(String phone, {String? label}) async {
    _setLoading(true);
    try {
      await service.addContactByPhone(phone, label: label);
      await refresh();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> remove(String userId) async {
    _setLoading(true);
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
