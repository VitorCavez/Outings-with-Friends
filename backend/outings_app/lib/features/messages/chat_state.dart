// lib/features/messages/chat_state.dart
import 'package:flutter/foundation.dart';
import '../../models/message.dart';

class ChatState extends ChangeNotifier {
  final String currentUserId;
  final String? peerUserId;
  final String? groupId;

  ChatState({required this.currentUserId, this.peerUserId, this.groupId});

  // ---- messages store ----
  final List<Message> _messages = <Message>[];
  final Map<String, int> _indexById = <String, int>{};

  // ---- ui state ----
  bool _typingPeer = false;

  // ---- pagination state ----
  String? _nextCursorIso; // null => no more pages
  bool _isFetchingHistory = false;

  // ---- getters ----
  List<Message> get messages => List.unmodifiable(_messages);
  bool get typingPeer => _typingPeer;

  String? get nextCursorIso => _nextCursorIso;
  bool get isFetchingHistory => _isFetchingHistory;
  bool get hasMoreHistory => _nextCursorIso != null;

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
    _resortAndReindex();
    notifyListeners();
    return added;
  }

  /// Incoming message from socket (may be from me or from peer).
  void addIncoming(Message m) {
    // If this is a server echo of my optimistic send, try to replace it
    if (m.isMine) {
      if (_absorbOptimisticEcho(m)) {
        _resortAndReindex();
        notifyListeners();
        return;
      }
    }
    _upsert(m, atStart: false);
  }

  /// Outgoing message I just sent (optimistic).
  void addOutgoing(Message m) {
    _upsert(m, atStart: false);
  }

  void setTyping(bool v) {
    if (_typingPeer == v) return;
    _typingPeer = v;
    notifyListeners();
  }

  void setNextCursor(String? iso) {
    _nextCursorIso = iso;
    notifyListeners();
  }

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

    _messages[idx] = old.copyWith(isRead: true);
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

  bool _contentEquivalent(Message a, Message b) {
    if (a.messageType != b.messageType) return false;

    // Text: exact text match (trimmed)
    if (!a.isImage && !a.isFile) {
      return a.text.trim() == b.text.trim();
    }

    // Attachments: allow equality by mediaUrl if present, otherwise by filename/size
    final urlA = a.mediaUrl ?? '';
    final urlB = b.mediaUrl ?? '';
    if (urlA.isNotEmpty && urlB.isNotEmpty) {
      return urlA == urlB;
    }
    final nameA = a.fileName ?? '';
    final nameB = b.fileName ?? '';
    final sizeA = a.fileSize ?? -1;
    final sizeB = b.fileSize ?? -1;
    return nameA == nameB && sizeA == sizeB;
  }

  /// Try to replace the most recent optimistic message with this server echo.
  /// We match by: same sender (me), same peer/group, content equivalence,
  /// and createdAt within a short window (±2 minutes).
  bool _absorbOptimisticEcho(Message serverCopy) {
    final int n = _messages.length;
    final DateTime t = serverCopy.createdAt;

    for (int i = n - 1; i >= 0; i--) {
      final cand = _messages[i];

      // Only consider outgoing optimistic-looking entries
      final isOptimisticId = cand.id.startsWith('tmp_') || cand.id.length < 8;
      if (!isOptimisticId) continue;

      // Must be my message and same chat target
      if (!cand.isMine) continue;
      final samePeer = cand.recipientId == serverCopy.recipientId;
      final sameGroup = cand.groupId == serverCopy.groupId;
      if (!(samePeer || sameGroup)) continue;

      // Content match (text or attachment heuristics)
      if (!_contentEquivalent(cand, serverCopy)) continue;

      // Close in time (±2 minutes)
      final diff = (cand.createdAt.difference(t)).inSeconds.abs();
      if (diff > 120) continue;

      // Replace optimistic with server copy
      _messages[i] = serverCopy;
      _indexById.remove(cand.id);
      _indexById[serverCopy.id] = i;
      return true;
    }
    return false;
  }

  /// Returns true if inserted as a new item; false if it was an update.
  bool _upsert(Message m, {required bool atStart, bool notify = true}) {
    final existing = _indexById[m.id];
    if (existing != null) {
      // Merge fields
      final old = _messages[existing];
      _messages[existing] = old.merge(m);
      if (notify) {
        _resortAndReindex();
        notifyListeners();
      }
      return false;
    } else {
      if (atStart) {
        _messages.insert(0, m);
        _reindexFromScratch();
      } else {
        _messages.add(m);
        _indexById[m.id] = _messages.length - 1;
      }
      if (notify) {
        _resortAndReindex();
        notifyListeners();
      }
      return true;
    }
  }

  void _resortAndReindex() {
    _messages.sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });
    _reindexFromScratch();
  }

  void _reindexFromScratch() {
    _indexById
      ..clear()
      ..addEntries(
        Iterable<int>.generate(
          _messages.length,
        ).map((i) => MapEntry(_messages[i].id, i)),
      );
  }
}
