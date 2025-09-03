// lib/features/messages/messages_repository.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/message.dart';
import '../../config/app_config.dart';

/// Paginated response wrapper
class MessagePage {
  final List<Message> items;
  final String? nextCursor; // null when no more pages
  const MessagePage({required this.items, this.nextCursor});
}

class MessagesRepository {
  final String _base;
  final Duration _timeout;

  MessagesRepository({String? baseUrl, Duration timeout = const Duration(seconds: 10)})
      : _base = _normalizeBase(baseUrl ?? AppConfig.apiBaseUrl),
        _timeout = timeout;

  // ---------------------------
  // Public API
  // ---------------------------

  /// Unified history entry point (cursor-based).
  /// - For direct chats, provide currentUserId + peerUserId
  /// - For group chats, provide currentUserId + groupId
  /// Optionally set `cursor` and `limit` for pagination.
  Future<MessagePage> history({
    required String currentUserId,
    String? peerUserId,
    String? groupId,
    String? cursor,
    int limit = 20,
  }) async {
    if ((peerUserId == null && groupId == null) ||
        (peerUserId != null && groupId != null)) {
      throw ArgumentError('Provide either peerUserId OR groupId (not both).');
    }

    return (peerUserId != null)
        ? _directHistory(
            currentUserId: currentUserId,
            peerUserId: peerUserId,
            cursor: cursor,
            limit: limit,
          )
        : _groupHistory(
            currentUserId: currentUserId,
            groupId: groupId!,
            cursor: cursor,
            limit: limit,
          );
  }

  /// NEW: Fetch any messages newer than `since`.
  /// If your backend supports `?since=<ISO8601>`, we’ll use it.
  /// If not, we still filter client-side to avoid duplicates.
  Future<List<Message>> historySince({
    required String currentUserId,
    String? peerUserId,
    String? groupId,
    DateTime? since,
    int? limit, // optional cap if server ignores since
  }) async {
    if ((peerUserId == null && groupId == null) ||
        (peerUserId != null && groupId != null)) {
      throw ArgumentError('Provide either peerUserId OR groupId (not both).');
    }

    return (peerUserId != null)
        ? _directHistorySince(
            currentUserId: currentUserId,
            peerUserId: peerUserId,
            since: since,
            limit: limit,
          )
        : _groupHistorySince(
            currentUserId: currentUserId,
            groupId: groupId!,
            since: since,
            limit: limit,
          );
  }

  // ---------------------------
  // Direct chat
  // ---------------------------

  Future<MessagePage> _directHistory({
    required String currentUserId,
    required String peerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    final qp = <String, String>{
      'peer': peerUserId,
      'currentUserId': currentUserId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    };

    final uri = Uri.parse('$_base/api/messages/direct').replace(queryParameters: qp);
    final res = await _get(uri);
    return _parsePage(res, currentUserId);
  }

  Future<List<Message>> _directHistorySince({
    required String currentUserId,
    required String peerUserId,
    DateTime? since,
    int? limit,
  }) async {
    final qp = <String, String>{
      'peer': peerUserId,
      'currentUserId': currentUserId,
      if (since != null) 'since': since.toUtc().toIso8601String(),
      if (limit != null) 'limit': '$limit',
    };

    final uri = Uri.parse('$_base/api/messages/direct').replace(queryParameters: qp);
    final res = await _get(uri);

    final list = _parseListOrItems(res, currentUserId);
    // client-side fallback filter in case server ignores ?since=
    if (since == null) return list;
    return list.where((m) => m.createdAt.isAfter(since)).toList();
  }

  // ---------------------------
  // Group chat
  // ---------------------------

  Future<MessagePage> _groupHistory({
    required String currentUserId,
    required String groupId,
    String? cursor,
    int limit = 20,
  }) async {
    // Prefer new paginated endpoint; backend also has legacy /group/:groupId which returns a list
    final qp = <String, String>{
      'groupId': groupId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    };

    final uri = Uri.parse('$_base/api/messages/group').replace(queryParameters: qp);
    final res = await _get(uri);
    return _parsePage(res, currentUserId);
  }

  Future<List<Message>> _groupHistorySince({
    required String currentUserId,
    required String groupId,
    DateTime? since,
    int? limit,
  }) async {
    final qp = <String, String>{
      'groupId': groupId,
      if (since != null) 'since': since.toUtc().toIso8601String(),
      if (limit != null) 'limit': '$limit',
    };

    final uri = Uri.parse('$_base/api/messages/group').replace(queryParameters: qp);
    final res = await _get(uri);

    final list = _parseListOrItems(res, currentUserId);
    if (since == null) return list;
    return list.where((m) => m.createdAt.isAfter(since)).toList();
  }

  // ---------------------------
  // HTTP helpers
  // ---------------------------

  Future<http.Response> _get(Uri uri) async {
    try {
      final res = await http
          .get(uri, headers: {HttpHeaders.acceptHeader: 'application/json'})
          .timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('HTTP ${res.statusCode}: ${res.body}');
      }
      return res;
    } on SocketException {
      rethrow;
    }
  }

  // ---------------------------
  // Parsing helpers
  // ---------------------------

  /// Parse a paginated response:
  /// - New shape: { items: [...], nextCursor: "..." }
  /// - Legacy shape: [ ... ]
  MessagePage _parsePage(http.Response res, String currentUserId) {
    final body = res.body.isEmpty ? '{}' : res.body;
    final decoded = json.decode(body);

    // New shape
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      final items = (decoded['items'] as List)
          .map((j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId))
          .toList();
      final nextCursor = decoded['nextCursor'] as String?;
      return MessagePage(items: items, nextCursor: nextCursor);
    }

    // Legacy shape (list)
    if (decoded is List) {
      final items = decoded
          .map((j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId))
          .toList();
      return MessagePage(items: items, nextCursor: null);
    }

    // Fallback: empty
    return const MessagePage(items: [], nextCursor: null);
  }

  /// Parse into a plain list regardless of {items}/array response.
  List<Message> _parseListOrItems(http.Response res, String currentUserId) {
    final body = res.body.isEmpty ? '{}' : res.body;
    final decoded = json.decode(body);

    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      return (decoded['items'] as List)
          .map((j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId))
          .toList();
    }

    if (decoded is List) {
      return decoded
          .map((j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId))
          .toList();
    }

    return const <Message>[];
  }
}

// Normalize baseUrl (no trailing slash)
String _normalizeBase(String base) {
  if (base.endsWith('/')) return base.substring(0, base.length - 1);
  return base;
}
