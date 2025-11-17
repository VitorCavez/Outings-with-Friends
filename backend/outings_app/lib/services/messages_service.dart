// lib/services/messages_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Lightweight wrapper around the messages endpoints.
/// Builds Authorization header on its own using ApiClient.authToken.
class MessagesService {
  MessagesService(this.api);
  final ApiClient api;

  Map<String, String>? _authHeaderOrNull() {
    final t = api.authToken;
    if (t == null || t.isEmpty) return null;
    return {'Authorization': 'Bearer $t'};
  }

  Map<String, dynamic> _asMap(dynamic body) {
    final dynamic json = body is String ? jsonDecode(body) : body;
    if (json is Map<String, dynamic>) return json;
    if (json is Map) return Map<String, dynamic>.from(json);
    throw StateError('Expected Map JSON response');
  }

  /// GET /api/messages/recent
  /// Returns a list of threads with a unified shape:
  /// { kind: 'group'|'dm', groupId?, peerId?, title, avatarUrl?, lastText, lastAt }
  Future<List<dynamic>> fetchRecent({int limit = 30}) async {
    final uri = Uri.parse(
      '${api.baseUrl}/api/messages/recent',
    ).replace(queryParameters: {'limit': '$limit'});
    final r = await http.get(uri, headers: _authHeaderOrNull());
    if (r.statusCode != 200) {
      throw Exception('Recent threads failed (${r.statusCode})');
    }
    final body = jsonDecode(r.body);
    if (body is Map && body['data'] is List) return body['data'] as List;
    if (body is List) return body;
    return const [];
  }

  /// GET /api/messages/direct?peer=&currentUserId=&cursor=&limit=
  Future<Map<String, dynamic>> fetchDirectHistory({
    required String currentUserId,
    required String peerUserId,
    String? cursor,
    int limit = 25,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/messages/direct').replace(
      queryParameters: {
        'peer': peerUserId,
        'currentUserId': currentUserId,
        if (cursor != null) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final r = await http.get(uri, headers: _authHeaderOrNull());
    if (r.statusCode != 200) {
      throw Exception('Direct history failed (${r.statusCode})');
    }
    return _asMap(r.body);
  }

  /// GET /api/messages/group?groupId=&cursor=&limit=
  Future<Map<String, dynamic>> fetchGroupHistory({
    required String groupId,
    String? cursor,
    int limit = 25,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/messages/group').replace(
      queryParameters: {
        'groupId': groupId,
        if (cursor != null) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final r = await http.get(uri, headers: _authHeaderOrNull());
    if (r.statusCode != 200) {
      throw Exception('Group history failed (${r.statusCode})');
    }
    return _asMap(r.body);
  }

  /// POST /api/messages
  Future<Map<String, dynamic>> sendDirect({
    required String senderId,
    required String recipientId,
    required String text,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/messages');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', ...?_authHeaderOrNull()},
      body: jsonEncode({
        'senderId': senderId,
        'recipientId': recipientId,
        'text': text,
      }),
    );
    if (r.statusCode != 201) {
      throw Exception('Send DM failed (${r.statusCode})');
    }
    return _asMap(r.body);
  }

  /// POST /api/messages/group/:groupId
  Future<Map<String, dynamic>> sendGroup({
    required String groupId,
    required String senderId,
    required String text,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/messages/group/$groupId');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', ...?_authHeaderOrNull()},
      body: jsonEncode({'senderId': senderId, 'text': text}),
    );
    if (r.statusCode != 201) {
      throw Exception('Send group message failed (${r.statusCode})');
    }
    return _asMap(r.body);
  }

  /// POST /api/messages/read { messageId, readerId }
  Future<void> markRead({
    required String messageId,
    required String readerId,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/messages/read');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', ...?_authHeaderOrNull()},
      body: jsonEncode({'messageId': messageId, 'readerId': readerId}),
    );
    if (r.statusCode != 200) {
      throw Exception('Mark read failed (${r.statusCode})');
    }
  }

  /// POST /api/messages/typing { isTyping, recipientId?, groupId?, userId }
  Future<void> sendTyping({
    required bool isTyping,
    required String userId,
    String? recipientId,
    String? groupId,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/messages/typing');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', ...?_authHeaderOrNull()},
      body: jsonEncode({
        'isTyping': isTyping,
        'userId': userId,
        if (recipientId != null) 'recipientId': recipientId,
        if (groupId != null) 'groupId': groupId,
      }),
    );
    if (r.statusCode != 200) {
      throw Exception('Typing notify failed (${r.statusCode})');
    }
  }
}
