// integration_test/outbox_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:outings_app/services/outbox_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Outbox queues offline and flushes online', (tester) async {
    // 👇 Pump a minimal app so the Windows integration runner can launch/stable-connect.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final outbox = OutboxService.instance;

    // Ensure the service is started (safe if already started).
    outbox.start();

    // Use fakes: record executions without real network.
    final sentMessages = <String>[];
    final sentChecklist = <String>[];

    outbox.setMessageExecutor((p) async {
      sentMessages.add('msg:${p.text}');
    });

    outbox.setChecklistExecutor((p) async {
      sentChecklist.add('chk:${p.outingId}:${p.itemId}:${p.checked}');
    });

    // Simulate offline
    outbox.setOnline(false);

    // Enqueue some tasks while offline
    await outbox.enqueueMessage(
      senderId: 'u1',
      recipientId: 'u1',
      text: 'hello-offline',
      messageType: 'text',
    );
    await outbox.enqueueChecklistUpdate(
      outingId: 'o1',
      itemId: 'i1',
      checked: true,
      note: 'offline-enqueue',
    );

    expect(outbox.pending, 2);

    // Go online -> should flush automatically
    outbox.setOnline(true);

    // Allow time for async flush
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // All tasks flushed
    expect(outbox.pending, 0);
    expect(sentMessages, contains('msg:hello-offline'));
    expect(sentChecklist, contains('chk:o1:i1:true'));
  });
}
