// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:outings_app/services/socket_service.dart'; // adjust path if needed
import 'package:outings_app/services/outbox_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _queueChecklist() async {
    // Demo IDs — replace with real ones later
    const outingId = 'demo-outing';
    const itemId = 'bring-snacks';

    await OutboxService.instance.enqueueChecklistUpdate(
      outingId: outingId,
      itemId: itemId,
      checked: true,
      note: 'Queued from Home screen',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                final socketService = SocketService();
                socketService.initSocket();
                socketService.sendMessage(
                  text: "Hello from Flutter!",
                  senderId: "YOUR_USER_ID",
                );
              },
              child: const Text('Send Socket Test Message'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _queueChecklist,
              child: const Text('Queue Checklist Update (Offline-capable)'),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: OutboxService.instance.pendingCount,
              builder: (_, count, __) => Text('Outbox pending: $count'),
            ),
          ],
        ),
      ),
    );
  }
}
