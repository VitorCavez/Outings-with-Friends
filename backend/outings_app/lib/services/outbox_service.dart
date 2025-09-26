// lib/services/outbox_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert'; // ✅ standard JSON

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../config/app_config.dart';

/// Types of outbox tasks we support.
enum OutboxType { message, checklist }

/// Message payload (you can extend as needed)
class MessagePayload {
  final String senderId;
  final String? recipientId;
  final String? groupId;
  final String text;
  final String? mediaUrl;
  final String? messageType;

  const MessagePayload({
    required this.senderId,
    required this.text,
    this.recipientId,
    this.groupId,
    this.mediaUrl,
    this.messageType,
  });
}

/// Checklist payload (generic)
class ChecklistPayload {
  final String outingId;
  final String itemId; // e.g. a checklist item id or client-generated key
  final bool checked;
  final String? note;

  const ChecklistPayload({
    required this.outingId,
    required this.itemId,
    required this.checked,
    this.note,
  });
}

/// A task that can be retried until it succeeds.
class OutboxTask {
  final String id;
  final OutboxType type;
  final Object payload;

  int attempts = 0;
  DateTime lastTried = DateTime.fromMillisecondsSinceEpoch(0);

  OutboxTask({
    required this.id,
    required this.type,
    required this.payload,
  });
}

/// Executors let us plug different send mechanisms (Socket or HTTP).
typedef MessageExecutor = Future<void> Function(MessagePayload p);
typedef ChecklistExecutor = Future<void> Function(ChecklistPayload p);

/// The OutboxService is a singleton that:
/// - Keeps a FIFO queue of tasks in memory
/// - Listens to connectivity changes
/// - Flushes when online, with basic backoff
class OutboxService {
  OutboxService._();
  static final OutboxService instance = OutboxService._();

  // Public stream to observe queue changes (optional)
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  // In-memory queue (can later be persisted to disk)
  final Queue<OutboxTask> _queue = Queue<OutboxTask>();

  // Executors (can be overridden from app code or tests)
  MessageExecutor? _messageExecutor;
  ChecklistExecutor? _checklistExecutor;

  // Optional socket reference for message send
  IO.Socket? _socket;

  // Connectivity
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _online = true; // assume online until proven otherwise
  bool _flushing = false;
  bool _started = false;

  /// Call once at app start.
  void start() {
    if (_started) return;
    _started = true;

    // Default executors: HTTP-based message sender; checklist unconfigured until you wire endpoint.
    _messageExecutor ??= _defaultHttpMessageSender;

    // Connectivity listener
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final isNowOnline = results.any((r) => r != ConnectivityResult.none);
      _online = isNowOnline;
      if (_online) {
        _flush();
      }
    });

    // Try initial flush shortly after start (e.g., app relaunch)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_online) _flush();
    });
  }

  /// Stop listening (mostly useful for tests)
  Future<void> stop() async {
    await _connSub?.cancel();
    _connSub = null;
    _started = false;
  }

  /// Allow wiring a socket emitter for messages.
  void setSocket(IO.Socket? socket) {
    _socket = socket;
    // If socket becomes available again, attempt a flush
    if (_online) _flush();
  }

  /// Override message sender
  void setMessageExecutor(MessageExecutor exec) {
    _messageExecutor = exec;
  }

  /// Override checklist sender
  void setChecklistExecutor(ChecklistExecutor exec) {
    _checklistExecutor = exec;
  }

  /// Manually set online/offline (handy for tests or manual toggles)
  void setOnline(bool online) {
    _online = online;
    if (_online) _flush();
  }

  // ---------- Public enqueue API --------------------------------------------

  Future<void> enqueueMessage({
    required String senderId,
    String? recipientId,
    String? groupId,
    required String text,
    String? mediaUrl,
    String? messageType,
  }) async {
    final id = _genId();
    _queue.add(OutboxTask(
      id: id,
      type: OutboxType.message,
      payload: MessagePayload(
        senderId: senderId,
        recipientId: recipientId,
        groupId: groupId,
        text: text,
        mediaUrl: mediaUrl,
        messageType: messageType,
      ),
    ));
    _notify();
    if (_online) _flush();
  }

  Future<void> enqueueChecklistUpdate({
    required String outingId,
    required String itemId,
    required bool checked,
    String? note,
  }) async {
    final id = _genId();
    _queue.add(OutboxTask(
      id: id,
      type: OutboxType.checklist,
      payload: ChecklistPayload(
        outingId: outingId,
        itemId: itemId,
        checked: checked,
        note: note,
      ),
    ));
    _notify();
    if (_online) _flush();
  }

  int get pending => _queue.length;

  // ---------- Internal: flush logic -----------------------------------------

  Future<void> _flush() async {
    if (_flushing) return;
    if (!_online) return;
    if (_queue.isEmpty) return;

    _flushing = true;
    try {
      // Simple linear pass; failed items are re-queued with basic delay/backoff
      final int startSize = _queue.length;
      for (int i = 0; i < startSize; i++) {
        final task = _queue.removeFirst();
        final success = await _process(task);
        if (!success) {
          // Basic backoff: wait a bit more for future retries
          task.attempts += 1;
          task.lastTried = DateTime.now();
          _queue.add(task);
        }
        _notify();
      }
    } finally {
      _flushing = false;
      // If still have items and still online, try again after a small delay
      if (_online && _queue.isNotEmpty) {
        Future.delayed(const Duration(seconds: 2), _flush);
      }
    }
  }

  Future<bool> _process(OutboxTask task) async {
    try {
      switch (task.type) {
        case OutboxType.message:
          final p = task.payload as MessagePayload;
          if (_messageExecutor == null) return false;
          await _messageExecutor!(p);
          return true;

        case OutboxType.checklist:
          final p2 = task.payload as ChecklistPayload;
          if (_checklistExecutor == null) {
            debugPrint('[outbox] checklist executor not set; keeping queued');
            return false;
          }
          await _checklistExecutor!(p2);
          return true;
      }
    } catch (e) {
      debugPrint('[outbox] task ${task.id} failed: $e');
      return false;
    }
  }

  void _notify() {
    pendingCount.value = _queue.length;
  }

  String _genId() => '${DateTime.now().millisecondsSinceEpoch}-${_rand5()}';

  String _rand5() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    return List.generate(5, (i) => chars[(now + i) % chars.length]).join();
  }

  // ---------- Default HTTP executors ----------------------------------------

  Future<void> _defaultHttpMessageSender(MessagePayload p) async {
    // If a socket is connected, prefer it for real-time send.
    if (_socket != null && _socket!.connected) {
      final payload = {
        'text': p.text,
        'senderId': p.senderId,
        'recipientId': p.recipientId,
        'groupId': p.groupId,
        'messageType': p.messageType ?? 'text',
        'mediaUrl': p.mediaUrl,
      };
      _socket!.emit('send_message', payload);
      return;
    }

    // Fallback to HTTP endpoint
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/messages');
    final body = <String, dynamic>{
      'senderId': p.senderId,
      'text': p.text,
      if (p.recipientId != null) 'recipientId': p.recipientId,
      if (p.groupId != null) 'groupId': p.groupId,
      if (p.mediaUrl != null) 'mediaUrl': p.mediaUrl,
      if (p.messageType != null) 'messageType': p.messageType,
    };

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body), // ✅ use standard encoder
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // Checklist: you must set an executor that matches your backend route.
  // Example executor (adjust endpoint to your API):
  static ChecklistExecutor buildHttpChecklistExecutor({
    required Future<String> Function() tokenProvider,
  }) {
    return (ChecklistPayload p) async {
      final token = await tokenProvider();
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/outings/${p.outingId}/checklist');
      final body = {
        'itemId': p.itemId,
        'checked': p.checked,
        if (p.note != null) 'note': p.note,
      };
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body), // ✅ use standard encoder
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
    };
  }
}
