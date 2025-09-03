// lib/features/messages/chat_state.dart
import 'package:flutter/foundation.dart';
import '../../models/message.dart';

class ChatState extends ChangeNotifier {
  final String currentUserId;
  final String? peerUserId;
  final String? groupId;

  ChatState({
    required this.currentUserId,
    this.peerUserId,
    this.groupId,
  });

  // ---- messages store ----
  final List<Message> _messages = <Message>[];
  final Map<String, int> _indexById = <String, int>{};

  // ---- ui state ----
  bool _typingPeer = false;

  // ---- pagination state ----
  // Backend returns nextCursor as ISO string (or null). When null => no more pages.
  String? _nextCursorIso;       // oldest page cursor to request next
  bool _isFetchingHistory = false;

  // ---- getters ----
  List<Message> get messages => List.unmodifiable(_messages);
  bool get typingPeer => _typingPeer;

  String? get nextCursorIso => _nextCursorIso;
  bool get isFetchingHistory => _isFetchingHistory;
  bool get hasMoreHistory => _nextCursorIso != null;

  /// Oldest timestamp currently loaded (useful if you want to compute your own cursor)
  DateTime? get oldestTimestamp =>
      _messages.isNotEmpty ? _messages.first.createdAt : null;

  // ---- public api ----

  /// Insert a batch of historical messages (e.g., from API).
  /// If `prepend` is true (default), they’re added at the top (oldest first).
  /// Returns number of messages actually added (dedup aware).
  int addHistory(List<Message> history, {bool prepend = true}) {
    if (history.isEmpty) return 0;
    var added = 0;

    if (prepend) {
      for (final m in history) {
        if (_upsert(m, atStart: true, notify: false)) added++;
      }
    } else {
      for (final m in history) {
        if (_upsert(m, atStart: false, notify: false)) added++;
      }
    }
    notifyListeners();
    return added;
  }

  void addIncoming(Message m) {
    _upsert(m, atStart: false); // new messages usually append
  }

  void addOutgoing(Message m) {
    _upsert(m, atStart: false);
  }

  void setTyping(bool v) {
    if (_typingPeer == v) return;
    _typingPeer = v;
    notifyListeners();
  }

  /// Update pagination cursor from API response (use null when no more pages)
  void setNextCursor(String? iso) {
    _nextCursorIso = iso;
    notifyListeners();
  }

  /// Mark that a history fetch has started/ended to avoid concurrent loads
  void setFetchingHistory(bool v) {
    if (_isFetchingHistory == v) return;
    _isFetchingHistory = v;
    notifyListeners();
  }

  void markRead(String messageId) {
    final idx = _indexById[messageId];
    if (idx == null) return;
    final old = _messages[idx];
    if (old.isRead) return;

    _messages[idx] = Message(
      id: old.id,
      text: old.text,
      senderId: old.senderId,
      recipientId: old.recipientId,
      groupId: old.groupId,
      createdAt: old.createdAt,
      isRead: true,
      isMine: old.isMine,
    );
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    _indexById.clear();
    _typingPeer = false;
    _nextCursorIso = null;
    _isFetchingHistory = false;
    notifyListeners();
  }

  // ---- helpers ----

  /// Returns true if inserted as a new item; false if it was an update to an existing id.
  bool _upsert(Message m, {required bool atStart, bool notify = true}) {
    final existing = _indexById[m.id];
    if (existing != null) {
      final old = _messages[existing];
      _messages[existing] = Message(
        id: m.id,
        text: m.text.isNotEmpty ? m.text : old.text,
        senderId: m.senderId.isNotEmpty ? m.senderId : old.senderId,
        recipientId: m.recipientId ?? old.recipientId,
        groupId: m.groupId ?? old.groupId,
        createdAt: m.createdAt.isAfter(old.createdAt) ? m.createdAt : old.createdAt,
        isRead: m.isRead || old.isRead,
        isMine: m.isMine,
      );
      if (notify) notifyListeners();
      return false;
    } else {
      if (atStart) {
        _messages.insert(0, m);
        _indexById.updateAll((_, i) => i + 1);
        _indexById[m.id] = 0;
      } else {
        _messages.add(m);
        _indexById[m.id] = _messages.length - 1;
      }
      if (notify) notifyListeners();
      return true;
    }
  }
}
