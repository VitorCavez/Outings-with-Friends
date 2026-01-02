// lib/services/contacts_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ContactsService {
  ContactsService({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Exception _friendlyError(String action, http.Response res) {
    // Try to parse { error: "...", message?: "..." }
    String? code;
    String? message;

    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        code = body['error']?.toString();
        message = body['message']?.toString();
      }
    } catch (_) {
      // ignore JSON parse failures
    }

    // Friendly mapping
    if (res.statusCode == 401 || res.statusCode == 403) {
      return Exception(
        '$action failed: session expired. Please log out and log in again.',
      );
    }

    if (res.statusCode == 404 && code == 'not_found') {
      return Exception('$action failed: no user found with that phone number.');
    }

    if (res.statusCode == 400 && code == 'invalid_phone') {
      return Exception('$action failed: invalid phone number format.');
    }

    // Fallback
    final extra = (message != null && message.isNotEmpty) ? ' ($message)' : '';
    return Exception('$action failed (${res.statusCode})$extra');
  }

  Future<Map<String, dynamic>?> lookupByPhone(
    String phone, {
    String defaultCountryCode = '+353',
  }) async {
    final uri = Uri.parse('$baseUrl/api/contacts/lookup-by-phone');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'phone': phone,
        'defaultCountryCode': defaultCountryCode,
      }),
    );

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['user'] as Map<String, dynamic>?;
    }

    if (res.statusCode == 404) return null;

    throw _friendlyError('Lookup user', res);
  }

  Future<void> addContactByPhone(
    String phone, {
    String? label,
    String defaultCountryCode = '+353',
  }) async {
    final uri = Uri.parse('$baseUrl/api/contacts');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'phone': phone,
        'defaultCountryCode': defaultCountryCode,
        if (label != null) 'label': label,
      }),
    );

    if (res.statusCode == 201 || res.statusCode == 200) return;

    throw _friendlyError('Add contact', res);
  }

  Future<void> addContactByUserId(String userId, {String? label}) async {
    final uri = Uri.parse('$baseUrl/api/contacts');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'userId': userId, if (label != null) 'label': label}),
    );

    if (res.statusCode == 201 || res.statusCode == 200) return;

    throw _friendlyError('Add contact', res);
  }

  Future<List<Map<String, dynamic>>> listContacts() async {
    final uri = Uri.parse('$baseUrl/api/contacts');
    final res = await http.get(uri, headers: _headers);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final List items = data['contacts'] as List? ?? [];
      return items.cast<Map<String, dynamic>>();
    }

    throw _friendlyError('List contacts', res);
  }

  Future<void> removeContact(String userId) async {
    final uri = Uri.parse('$baseUrl/api/contacts/$userId');
    final res = await http.delete(uri, headers: _headers);

    if (res.statusCode == 200) return;

    throw _friendlyError('Remove contact', res);
  }

  Future<void> createInvite(
    String toUserId, {
    String source = 'contacts',
    String? message,
  }) async {
    final uri = Uri.parse('$baseUrl/api/invites');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'toUserId': toUserId,
        'source': source,
        if (message != null) 'message': message,
      }),
    );

    if (res.statusCode == 201) return;

    throw _friendlyError('Create invite', res);
  }
}
