// lib/services/socket_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as IO;
// If you later target web, consider conditional imports for dart:io.
import 'dart:io' show Platform;

import '../config/app_config.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  final _conn$ = StreamController<bool>.broadcast();
  Stream<bool> get connection$ => _conn$.stream;

  final List<_Queued> _outbox = <_Queued>[];

  String? _overrideBaseUrl;

  String _resolveBaseUrl() {
    if (_overrideBaseUrl != null && _overrideBaseUrl!.isNotEmpty) {
      return _overrideBaseUrl!;
    }
    final cfg = AppConfig.socketBaseUrl.trim();
    if (cfg.isNotEmpty) return cfg;

    // Dev fallbacks
    if (kIsWeb) return 'http://127.0.0.1:3000';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }

  void setBaseUrl(String baseUrl) {
    _overrideBaseUrl = baseUrl.trim();
    if (_socket != null) {
      try {
        _socket!.dispose();
      } catch (_) {}
      _socket = null;
    }
  }

  void initSocket({
    String? baseUrl,
    String path = '/socket.io',
    bool autoConnect = true,
    String? userId,
  }) {
    final url = (baseUrl ?? _resolveBaseUrl()).replaceAll(RegExp(r'/+$'), '');
    if (_socket != null) {
      if (autoConnect && _socket!.disconnected) _socket!.connect();
      return;
    }

    // Build options as a plain map to be compatible with all versions
    final Map<String, dynamic> opts = {
      'transports': ['websocket'],
      'path': path,
      'reconnection': true,
      'reconnectionAttempts': 15,
      'reconnectionDelay': 800, // ms
      'timeout': 10000, // connect timeout ms
      'autoConnect': autoConnect,
      'auth': userId != null ? {'userId': userId} : <String, dynamic>{},
    };

    _socket = IO.io(url, opts);
    _attachListeners(url);

    if (autoConnect) _socket!.connect();
  }

  void connect() => initSocket();

  IO.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected == true;

  void on(String event, void Function(dynamic data) handler) {
    _socket?.on(event, handler);
  }

  void off(String event, [void Function(dynamic data)? handler]) {
    if (handler != null) {
      _socket?.off(event, handler);
    } else {
      _socket?.off(event);
    }
  }

  void _attachListeners(String urlForLogs) {
    if (_socket == null) return;

    _socket!
      ..off('connect')
      ..off('disconnect')
      ..off('error')
      ..off('connect_error')
      ..off('reconnect')
      ..off('reconnect_attempt')
      ..onConnect((_) {
        debugPrint('🔌 Socket connected → $urlForLogs');
        _conn$.add(true);
        _flushOutbox();
      })
      ..onDisconnect((_) {
        debugPrint('🔌 Socket disconnected');
        _conn$.add(false);
      })
      ..onError((err) {
        debugPrint('❌ socket error: $err');
        _conn$.add(false);
      })
      ..on('connect_error', (err) {
        debugPrint('❌ connect_error → $err (url=$urlForLogs)');
        _conn$.add(false);
      })
      ..on('reconnect_attempt', (n) {
        debugPrint('🔁 reconnect attempt #$n …');
      })
      ..on('reconnect', (n) {
        debugPrint('✅ reconnected after $n attempt(s)');
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

  void _safeEmit(String event, Map<String, dynamic> payload) {
    _ensureReady();
    if (isConnected) {
      _socket!.emit(event, payload);
    } else {
      _outbox.add(_Queued(event, payload, DateTime.now()));
    }
  }

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
    String? messageType,
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

  void sendTyping({
    required bool isTyping,
    String? recipientId,
    String? groupId,
  }) {
    _safeEmit('typing', {
      'isTyping': isTyping,
      'recipientId': recipientId,
      'groupId': groupId,
    });
  }

  void sendRead(String messageId) {
    _safeEmit('read_message', {'messageId': messageId});
  }

  void subscribePresence(String peerUserId) {
    /* no-op for now */
  }
  void unsubscribePresence(String peerUserId) {
    /* no-op */
  }
  void queryPresence(String peerUserId) {
    _safeEmit('presence_query', {'peerUserId': peerUserId});
  }

  void joinGroup(String groupId) {
    if (groupId.trim().isEmpty) return;
    _safeEmit('join_group', {'groupId': groupId});
  }

  void leaveGroup(String groupId) {
    if (groupId.trim().isEmpty) return;
    _safeEmit('leave_group', {'groupId': groupId});
  }

  void refreshGroups() {
    _safeEmit('refresh_groups', {});
  }

  void sendTestMessage() {
    _safeEmit('test', {'message': 'Hello from Flutter!'});
  }

  void disconnect() {
    _socket?.disconnect();
  }

  void dispose() {
    _conn$.close();
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }
}

class _Queued {
  final String event;
  final Map<String, dynamic> payload;
  final DateTime enqueuedAt;
  _Queued(this.event, this.payload, this.enqueuedAt);
}
