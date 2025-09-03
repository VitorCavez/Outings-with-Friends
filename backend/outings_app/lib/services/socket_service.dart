// lib/services/socket_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:socket_io_client/socket_io_client.dart' as IO;
// NOTE: Don't import 'dart:io' directly on web. We'll gate it with kIsWeb.
import 'dart:io' show Platform;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  // ---- NEW: connection status stream (true=connected, false=disconnected)
  final StreamController<bool> _conn$ = StreamController<bool>.broadcast();
  Stream<bool> get connection$ => _conn$.stream;

  // ---- NEW: outbox queue for unsent events
  final List<_Queued> _outbox = <_Queued>[];

  String _defaultBaseUrl() {
    if (kIsWeb) return 'http://localhost:4000';
    if (Platform.isAndroid) return 'http://10.0.2.2:4000';
    if (Platform.isIOS) return 'http://127.0.0.1:4000';
    return 'http://localhost:4000';
  }

  void initSocket({
    String? baseUrl,
    String path = '/socket.io',
    bool autoConnect = true,
    String? userId, // optional: to support presence/targeted rooms
  }) {
    final url = baseUrl ?? _defaultBaseUrl();

    if (_socket != null) {
      if (autoConnect && _socket!.disconnected) _socket!.connect();
      return;
    }

    // We’ll pass userId via `auth` so backend can put the socket in a user room.
    final builder = IO.OptionBuilder()
        .setTransports(['websocket'])
        .setPath(path)
        .setAuth(userId != null ? {'userId': userId} : {})
        // v2 builder has no setAutoConnect; use disableAutoConnect when needed.
        ;

    final opts = (autoConnect) ? builder.build() : builder.disableAutoConnect().build();

    _socket = IO.io(url, opts);
    _attachListeners();

    if (autoConnect) _socket!.connect();
  }

  void connect() => initSocket();

  IO.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected == true;

  // Allow consumers to subscribe to any event without exposing _socket
  void on(String event, void Function(dynamic data) handler) {
    _socket?.on(event, handler);
  }

  // Allow removing listeners
  void off(String event, [void Function(dynamic data)? handler]) {
    if (handler != null) {
      _socket?.off(event, handler);
    } else {
      _socket?.off(event);
    }
  }

  void _attachListeners() {
    if (_socket == null) return;

    _socket!
      ..off('connect')
      ..off('disconnect')
      ..off('error')
      ..off('connect_error')
      ..off('reconnect')
      ..off('reconnect_attempt')
      ..onConnect((_) {
        _conn$.add(true);
        _flushOutbox();
      })
      ..onDisconnect((_) {
        _conn$.add(false);
      })
      ..onError((err) {
        _conn$.add(false);
      })
      ..on('connect_error', (_) {
        _conn$.add(false);
      })
      ..on('reconnect', (_) {
        _conn$.add(true);
        _flushOutbox();
      });
  }

  void _ensureReady() {
    if (_socket == null) {
      initSocket();
    } else if (_socket!.disconnected) {
      _socket!.connect();
    }
  }

  // ---- NEW: central emit that queues if offline
  void _safeEmit(String event, Map<String, dynamic> payload) {
    _ensureReady();
    if (isConnected) {
      _socket!.emit(event, payload);
    } else {
      _outbox.add(_Queued(event, payload, DateTime.now()));
    }
  }

  // ---- NEW: flush queue on reconnect
  void _flushOutbox() {
    if (!isConnected || _outbox.isEmpty) return;
    for (final q in _outbox) {
      _socket!.emit(q.event, q.payload);
    }
    _outbox.clear();
  }

  // ---- App-level API
  void sendMessage({
    required String text,
    required String senderId,
    String? groupId,
    String? recipientId,
    String? messageType, // 'text' | 'image' ...
    String? mediaUrl,
    String? fileName,
    int? fileSize,
  }) {
    _safeEmit('send_message', {
      'text': text,
      'senderId': senderId,
      'groupId': groupId,
      'recipientId': recipientId,
      'messageType': messageType ?? 'text',
      'mediaUrl': mediaUrl,
      'fileName': fileName,
      'fileSize': fileSize,
    });
  }

  void sendTyping({required bool isTyping, String? recipientId, String? groupId}) {
    _safeEmit('typing', {
      'isTyping': isTyping,
      'recipientId': recipientId,
      'groupId': groupId,
    });
  }

  void sendRead(String messageId) {
    _safeEmit('read_message', {'messageId': messageId});
  }

  void sendTestMessage() {
    _safeEmit('test', {'message': 'Hello from Flutter!'});
  }

  void disconnect() {
    _socket?.disconnect();
  }

  void dispose() {
    _conn$.close();
    _socket?.dispose();
    _socket = null;
  }
}

class _Queued {
  final String event;
  final Map<String, dynamic> payload;
  final DateTime enqueuedAt;
  _Queued(this.event, this.payload, this.enqueuedAt);
}
