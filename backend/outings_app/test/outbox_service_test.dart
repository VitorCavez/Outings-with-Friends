// test/outbox_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:outings_app/services/outbox_service.dart';

void main() {
  group('OutboxService (unit)', () {
    final outbox = OutboxService.instance;

    setUp(() {
      // Ensure clean state before each test
      outbox.stop();
      // Since we don’t have a reset API, we simulate a new start with zero listeners
      outbox.start();
      // Force offline by default to avoid unexpected flushes
      outbox.setOnline(false);
    });

    test('enqueues messages in FIFO order and flushes online', () async {
      final sent = <String>[];

      outbox.setMessageExecutor((p) async {
        sent.add(p.text);
      });

      await outbox.enqueueMessage(senderId: 'u', recipientId: 'u', text: 'm1');
      await outbox.enqueueMessage(senderId: 'u', recipientId: 'u', text: 'm2');
      await outbox.enqueueMessage(senderId: 'u', recipientId: 'u', text: 'm3');

      expect(outbox.pending, 3);

      // Go online -> should flush in order
      outbox.setOnline(true);

      // Give the service a moment to process
      await Future.delayed(const Duration(milliseconds: 300));

      expect(outbox.pending, 0);
      expect(sent, ['m1', 'm2', 'm3']);
    });

    test('failed tasks are retried and kept in the queue', () async {
      int attempts = 0;

      outbox.setMessageExecutor((p) async {
        attempts++;
        if (attempts < 2) {
          throw Exception('simulate failure once');
        }
        // success on second try
      });

      await outbox.enqueueMessage(senderId: 'u', recipientId: 'u', text: 'will-retry');

      // Go online -> first attempt fails, task remains
      outbox.setOnline(true);
      await Future.delayed(const Duration(milliseconds: 200));
      // Still pending because the loop re-queued it
      expect(outbox.pending, 1);

      // Allow retry loop (Outbox schedules a delayed re-flush)
      await Future.delayed(const Duration(seconds: 3));

      // Ultimately should flush successfully
      expect(outbox.pending, 0);
      expect(attempts, greaterThanOrEqualTo(2));
    });

    test('checklist executor is required; without it tasks remain queued', () async {
      // Remove checklist executor to simulate "not wired yet"
      outbox.setChecklistExecutor((_) async {
        throw UnimplementedError('temporarily disable for test');
      });

      await outbox.enqueueChecklistUpdate(
        outingId: 'o1',
        itemId: 'i1',
        checked: true,
      );

      outbox.setOnline(true);
      await Future.delayed(const Duration(milliseconds: 200));

      // Task failed and should still be in queue (will retry later)
      expect(outbox.pending, 1);
    });
  });
}
