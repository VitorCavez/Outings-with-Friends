// lib/features/messages/messages_repository.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/message.dart';
import '../../config/app_config.dart';

/// Paginated response wrapper
class MessagePage {
  final List<Message> items;
  final String? nextCursor; // null when no more pages
  const MessagePage({required this.items, this.nextCursor});
}

/// Unified recent entry for Chats tab
class RecentThread {
  /// 'dm' or 'group'
  final String kind;

  /// peer user id if kind == 'dm', otherwise null
  final String? peerId;

  /// group id if kind == 'group', otherwise null
  final String? groupId;

  /// latest message in this thread
  final Message last;

  const RecentThread.dm({required this.peerId, required this.last})
    : kind = 'dm',
      groupId = null;

  const RecentThread.group({required this.groupId, required this.last})
    : kind = 'group',
      peerId = null;

  String get id => peerId ?? groupId ?? '';
}

class MessagesRepository {
  // ---- singleton ------------------------------------------------------------
  static final MessagesRepository _i = MessagesRepository._internal(
    baseUrl: AppConfig.apiBaseUrl,
    timeout: const Duration(seconds: 10),
  );
  factory MessagesRepository() => _i;

  MessagesRepository._internal({
    required String baseUrl,
    required Duration timeout,
  }) : _base = _normalizeBase(baseUrl),
       _timeout = timeout;

  // ---- config ---------------------------------------------------------------
  final String _base;
  final Duration _timeout;

  // Optional Authorization header (Bearer). Set this once after login.
  static String? _authToken;
  static void setAuthToken(String? token) => _authToken = token;

  Map<String, String> _headers() => {
    HttpHeaders.acceptHeader: 'application/json',
    if (_authToken != null && _authToken!.isNotEmpty)
      HttpHeaders.authorizationHeader: 'Bearer $_authToken',
  };

  // ---- simple caches (in-memory) -------------------------------------------
  final Map<String, List<Message>> _dmCache = <String, List<Message>>{};
  final Map<String, List<Message>> _groupCache = <String, List<Message>>{};

  /// Notifies listeners when any cache changes (for Recent Chats UI).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  void _bump() => revision.value = revision.value + 1;

  // ---- DM helpers -----------------------------------------------------------
  List<Message> getCachedDm(String peerUserId) =>
      List<Message>.from(_dmCache[peerUserId] ?? const []);
  Iterable<String> get dmPeers => _dmCache.keys;

  /// Latest message for a peer (null if none). Assumes per-peer list is sorted asc.
  Message? latestForPeer(String peerUserId) {
    final list = _dmCache[peerUserId];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  void putDmMessages(
    String peerUserId,
    List<Message> msgs, {
    bool prepend = false,
  }) {
    final existing = _dmCache[peerUserId] ?? <Message>[];
    final merged = _mergeUniqueSorted(existing, msgs, prepend: prepend);
    _dmCache[peerUserId] = merged;
    _bump();
  }

  void upsertOne(String peerUserId, Message m) {
    final existing = _dmCache[peerUserId] ?? <Message>[];
    final idx = existing.indexWhere((x) => x.id == m.id);
    if (idx >= 0) {
      existing[idx] = m;
    } else {
      existing.add(m);
    }
    existing.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // asc
    _dmCache[peerUserId] = existing;

    // 🔔 unseen logic (only for incoming, only for the peer we are NOT viewing)
    final viewing = activePeer.value == peerUserId;
    if (!m.isMine && !viewing) {
      _unseenByPeer.update(peerUserId, (v) => v + 1, ifAbsent: () => 1);
      _recomputeUnseenTotal();
    }

    _bump();
  }

  // ---- Group helpers --------------------------------------------------------
  List<Message> getCachedGroup(String groupId) =>
      List<Message>.from(_groupCache[groupId] ?? const []);
  Iterable<String> get groupIds => _groupCache.keys;

  Message? latestForGroup(String groupId) {
    final list = _groupCache[groupId];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  void putGroupMessages(
    String groupId,
    List<Message> msgs, {
    bool prepend = false,
  }) {
    final existing = _groupCache[groupId] ?? <Message>[];
    final merged = _mergeUniqueSorted(existing, msgs, prepend: prepend);
    _groupCache[groupId] = merged;
    _bump();
  }

  void upsertGroupOne(String groupId, Message m) {
    final existing = _groupCache[groupId] ?? <Message>[];
    final idx = existing.indexWhere((x) => x.id == m.id);
    if (idx >= 0) {
      existing[idx] = m;
    } else {
      existing.add(m);
    }
    existing.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // asc
    _groupCache[groupId] = existing;

    // (Optional) unseen per-group; mirrored pattern as DM unseen
    final viewingGroup = activeGroup.value == groupId;
    if (!m.isMine && !viewingGroup) {
      _unseenByGroup.update(groupId, (v) => v + 1, ifAbsent: () => 1);
      _recomputeUnseenTotal();
    }

    _bump();
  }

  // ---- Unseen counters ------------------------------------------------------
  /// Who the UI is currently viewing in a DM thread (null = no DM open).
  final ValueNotifier<String?> activePeer = ValueNotifier<String?>(null);

  /// Who the UI is currently viewing in a Group thread (null = no group open).
  final ValueNotifier<String?> activeGroup = ValueNotifier<String?>(null);

  /// Per-peer unseen counts (DMs).
  final Map<String, int> _unseenByPeer = <String, int>{};

  /// Per-group unseen counts.
  final Map<String, int> _unseenByGroup = <String, int>{};

  /// Total unseen across all threads for the bottom-bar badge.
  final ValueNotifier<int> unseenTotal = ValueNotifier<int>(0);

  void _recomputeUnseenTotal() {
    int sum = 0;
    for (final v in _unseenByPeer.values) sum += v;
    for (final v in _unseenByGroup.values) sum += v;
    if (unseenTotal.value != sum) unseenTotal.value = sum;
  }

  /// Call when opening a DM thread; resets unseen.
  void setActivePeer(String? peerId) {
    activePeer.value = peerId;
    if (peerId == null) return;
    if (_unseenByPeer.remove(peerId) != null) {
      _recomputeUnseenTotal();
    }
  }

  /// Call when opening a Group thread; resets unseen.
  void setActiveGroup(String? groupId) {
    activeGroup.value = groupId;
    if (groupId == null) return;
    if (_unseenByGroup.remove(groupId) != null) {
      _recomputeUnseenTotal();
    }
  }

  /// Back-compat with older call sites (DM only).
  void markThreadSeen(String peerId) => clearUnseen(peerId);

  void clearUnseen(String peerId) {
    if (_unseenByPeer.remove(peerId) != null) {
      _recomputeUnseenTotal();
    }
  }

  // ---------------------------
  // Public API
  // ---------------------------

  /// Unified history entry point (cursor-based).
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

  /// Fetch messages newer than `since` (helper for live refresh).
  Future<List<Message>> historySince({
    required String currentUserId,
    String? peerUserId,
    String? groupId,
    DateTime? since,
    int? limit,
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

  /// Build a unified recent list (DM + Group) from local caches.
  /// Sorts by latest message time descending.
  List<RecentThread> recentThreads() {
    final out = <RecentThread>[];

    // DMs
    for (final peer in dmPeers) {
      final last = latestForPeer(peer);
      if (last != null) out.add(RecentThread.dm(peerId: peer, last: last));
    }

    // Groups
    for (final gid in groupIds) {
      final last = latestForGroup(gid);
      if (last != null) out.add(RecentThread.group(groupId: gid, last: last));
    }

    out.sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
    return out;
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

    final uri = Uri.parse(
      '$_base/api/messages/direct',
    ).replace(queryParameters: qp);
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

    final uri = Uri.parse(
      '$_base/api/messages/direct',
    ).replace(queryParameters: qp);
    final res = await _get(uri);

    final list = _parseListOrItems(res, currentUserId);
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
    final qp = <String, String>{
      'groupId': groupId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    };

    final uri = Uri.parse(
      '$_base/api/messages/group',
    ).replace(queryParameters: qp);
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

    final uri = Uri.parse(
      '$_base/api/messages/group',
    ).replace(queryParameters: qp);
    final res = await _get(uri);

    final list = _parseListOrItems(res, currentUserId);
    if (since == null) return list;
    return list.where((m) => m.createdAt.isAfter(since)).toList();
  }

  // ---------------------------
  // HTTP helpers
  // ---------------------------

  Future<http.Response> _get(Uri uri) async {
    final res = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return res;
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
          .map(
            (j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId),
          )
          .toList();
      final nextCursor = decoded['nextCursor'] as String?;
      return MessagePage(items: items, nextCursor: nextCursor);
    }

    // Legacy shape (list)
    if (decoded is List) {
      final items = decoded
          .map(
            (j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId),
          )
          .toList();
      return const MessagePage(
        items: [],
        nextCursor: null,
      ).copyWith(items: items);
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
          .map(
            (j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId),
          )
          .toList();
    }

    if (decoded is List) {
      return decoded
          .map(
            (j) => Message.fromMap(Map<String, dynamic>.from(j), currentUserId),
          )
          .toList();
    }

    return const <Message>[];
  }

  /// Merge + de-dup by id and keep ascending order by createdAt.
  List<Message> _mergeUniqueSorted(
    List<Message> a,
    List<Message> b, {
    required bool prepend,
  }) {
    final map = <String, Message>{for (final m in a) m.id: m};
    for (final m in b) {
      map[m.id] = m; // upsert
    }
    final list = map.values.toList()
      ..sort((x, y) => x.createdAt.compareTo(y.createdAt)); // asc
    return list;
  }
}

// Helper to normalize base URL (no trailing slash).
String _normalizeBase(String base) =>
    base.endsWith('/') ? base.substring(0, base.length - 1) : base;

// Small extension to keep _parsePage concise.
extension on MessagePage {
  MessagePage copyWith({List<Message>? items, String? nextCursor}) =>
      MessagePage(
        items: items ?? this.items,
        nextCursor: nextCursor ?? this.nextCursor,
      );
}
