// integration_test/combined_desktop_test.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:outings_app/routes/app_router.dart';
import 'package:outings_app/services/outbox_service.dart';

Future<void> _bootIntoShell(WidgetTester tester) async {
  // Pump the router app
  await tester.pumpWidget(MaterialApp.router(routerConfig: AppRouter.router));

  // Let SplashScreen's 2s timer complete, then settle.
  await tester.pump(const Duration(milliseconds: 2100));
  await tester.pumpAndSettle();

  // If a shell isn't mounted yet, try routing to /home explicitly.
  if (find.byType(BottomNavigationBar).evaluate().isEmpty) {
    AppRouter.router.go('/home');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
}

void main() {
  tearDown(() async {
    if (Platform.isWindows) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  });
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Combined: tab UI + Outbox offline/online flush', (tester) async {
    await _bootIntoShell(tester);

    // --- Tab UI assertions (like app_flow_test) ---
    expect(find.byKey(const Key('tab-plan')), findsOneWidget);
    expect(find.byKey(const Key('tab-discover')), findsOneWidget);
    expect(find.byKey(const Key('tab-groups')), findsOneWidget);
    expect(find.byKey(const Key('tab-calendar')), findsOneWidget);
    expect(find.byKey(const Key('tab-messages')), findsOneWidget);

    // Switch around a bit
    await tester.tap(find.byKey(const Key('tab-discover')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fab-home')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-groups')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fab-home')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-plan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fab-home')), findsNothing);

    // --- Outbox flow (like outbox_test), no relaunch ---
    final outbox = OutboxService.instance;

    // Use fake executors to avoid network, but still exercise the outbox.
    final sentMsgs = <String>[];
    final sentChecklist = <String>[];

    outbox.setMessageExecutor((p) async {
      sentMsgs.add(p.text);
    });

    outbox.setChecklistExecutor((p) async {
      sentChecklist.add('${p.outingId}:${p.itemId}:${p.checked}');
    });

    // Start clean and force offline
    outbox.start();
    outbox.setOnline(false);

    // Enqueue while offline
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
      note: 'from-combined-test',
    );

    // Should be queued
    expect(outbox.pending, 2);

    // Go online -> should auto-flush
    outbox.setOnline(true);

    // Allow the async worker to run
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Flushed
    expect(outbox.pending, 0);
    expect(sentMsgs, contains('hello-offline'));
    expect(sentChecklist, contains('o1:i1:true'));
  });
}
