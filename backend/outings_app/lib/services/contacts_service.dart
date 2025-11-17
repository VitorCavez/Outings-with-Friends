// lib/services/contacts_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ContactsService {
  ContactsService({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

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
      return jsonDecode(res.body)['user'] as Map<String, dynamic>?;
    }
    if (res.statusCode == 404) return null;
    throw Exception('Lookup failed (${res.statusCode})');
  }

  Future<void> addContactByPhone(String phone, {String? label}) async {
    final uri = Uri.parse('$baseUrl/api/contacts');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'phone': phone, if (label != null) 'label': label}),
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Add contact failed (${res.statusCode})');
    }
  }

  Future<void> addContactByUserId(String userId, {String? label}) async {
    final uri = Uri.parse('$baseUrl/api/contacts');
    final res = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'userId': userId, if (label != null) 'label': label}),
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Add contact failed (${res.statusCode})');
    }
  }

  Future<List<Map<String, dynamic>>> listContacts() async {
    final uri = Uri.parse('$baseUrl/api/contacts');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final List items = data['contacts'] as List? ?? [];
      return items.cast<Map<String, dynamic>>();
    }
    throw Exception('List contacts failed (${res.statusCode})');
  }

  Future<void> removeContact(String userId) async {
    final uri = Uri.parse('$baseUrl/api/contacts/$userId');
    final res = await http.delete(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('Remove contact failed (${res.statusCode})');
    }
  }

  // Optional: create invite to a user (e.g., from public feed chip)
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
    if (res.statusCode != 201) {
      throw Exception('Create invite failed (${res.statusCode})');
    }
  }
}
