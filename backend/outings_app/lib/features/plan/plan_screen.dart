import 'package:flutter/material.dart';
import '../../services/socket_service.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final TextEditingController _messageController = TextEditingController();
  final SocketService _socketService = SocketService();

  @override
  void initState() {
    super.initState();
    // was: _socketService.connect();
    _socketService.initSocket();
  }

  void _sendTestMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // was: _socketService.sendMessage(message, 'sender', null, 'recipient');
    _socketService.sendMessage(
      text: message,
      senderId: '698381fc-ad46-49b0-94c5-3f6c94534bc9', // TODO: real user id
      // groupId: null, // optional
      recipientId: 'bdb74dc7-d499-4fa1-ba4f-ed4ce1d0be9b', // TODO: real recipient
    );
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("📡 Socket Messaging Test"),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(labelText: 'Enter message'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                // Reuse the same singleton instance
                _socketService.initSocket(); // safe to call; no-op if already connected
                _socketService.sendTestMessage();
              },
              child: const Text("Send Test Socket Message"),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _sendTestMessage,
              child: const Text("Send Message via sendMessage()"),
            ),
          ],
        ),
      ),
    );
  }
}
