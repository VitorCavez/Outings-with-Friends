// lib/features/messages/messages_screen.dart
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../config/app_config.dart';
import '../../services/outbox_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _controller = TextEditingController();
  IO.Socket? _socket;
  String _status = 'Not connected';
  bool _closing = false; // prevent setState after dispose

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  void _safeSetState(void Function() fn) {
    if (!_closing && mounted) setState(fn);
  }

  void _connectSocket() {
    try {
      if (_socket != null) return;

      const userId = 'test-user'; // replace with real user id when auth is ready

      final socket = IO.io(
        AppConfig.apiBaseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setQuery({'userId': userId})
            .disableAutoConnect()
            .build(),
      );

      socket.onConnect((_) {
        _safeSetState(() => _status = 'Connected to ${AppConfig.apiBaseUrl}');
      });

      socket.onDisconnect((_) {
        _safeSetState(() => _status = 'Disconnected');
      });

      socket.on('receive_message', (data) {
        if (_closing || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('receive_message: ${data.toString()}')),
        );
      });

      _socket = socket;

      // Let Outbox prefer socket when available (falls back to HTTP otherwise)
      OutboxService.instance.setSocket(_socket);

      _socket!.connect();
    } catch (e) {
      _safeSetState(() => _status = 'Socket error: $e');
    }
  }

  @override
  void dispose() {
    _closing = true;
    _controller.dispose();

    try {
      _socket?.off('receive_message');
      _socket?.off('connect');
      _socket?.off('disconnect');
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    OutboxService.instance.setSocket(null);

    super.dispose();
  }

  Future<void> _enqueueViaOutbox() async {
    final txt = _controller.text.trim();
    if (txt.isEmpty) return;

    await OutboxService.instance.enqueueMessage(
      senderId: 'test-user',
      recipientId: 'test-user', // or groupId: '...'
      text: txt,
      messageType: 'text',
    );

    if (!mounted) return;
    _controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queued to Outbox (auto-sends when online)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          const SizedBox(height: 60),
          const Center(
            child: Text(
              '💬 Messages (Offline-capable via Outbox)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(_status, style: const TextStyle(color: Colors.grey))),
          const SizedBox(height: 8),
          Center(
            child: ValueListenableBuilder<int>(
              valueListenable: OutboxService.instance.pendingCount,
              builder: (_, count, __) => Text(
                'Outbox pending: $count',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Enter message'),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(border: UnderlineInputBorder()),
            onSubmitted: (_) => _enqueueViaOutbox(),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton(
              onPressed: _enqueueViaOutbox,
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
