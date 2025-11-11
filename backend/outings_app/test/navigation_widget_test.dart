// test/navigation_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outings_app/routes/app_router.dart';

Future<void> _ensureAtShell(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: AppRouter.router));
  // Let SplashScreen's delayed auth/navigation finish (≈2s)
  await tester.pump(const Duration(milliseconds: 2100));
  await tester.pumpAndSettle();

  // If still no bottom bar, try to force a shell path
  if (find.byType(BottomNavigationBar).evaluate().isEmpty) {
    AppRouter.router.go('/home');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Bottom bar shows tabs and Home has no FAB', (tester) async {
    await _ensureAtShell(tester);

    // Tabs exist (icon keys on BottomNavigationBarItem)
    expect(find.byKey(const Key('tab-plan')), findsOneWidget);
    expect(find.byKey(const Key('tab-discover')), findsOneWidget);
    expect(find.byKey(const Key('tab-groups')), findsOneWidget);
    expect(find.byKey(const Key('tab-calendar')), findsOneWidget);
    expect(find.byKey(const Key('tab-messages')), findsOneWidget);

    // On home/plan, back-to-home FAB should NOT be visible
    expect(find.byKey(const Key('fab-home')), findsNothing);
  });

  testWidgets('Switching tabs reveals the back-to-home FAB', (tester) async {
    await _ensureAtShell(tester);

    // Tap Discover
    await tester.tap(find.byKey(const Key('tab-discover')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fab-home')), findsOneWidget);

    // Tap Groups
    await tester.tap(find.byKey(const Key('tab-groups')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fab-home')), findsOneWidget);

    // Back to Plan (Home)
    await tester.tap(find.byKey(const Key('tab-plan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fab-home')), findsNothing);
  });

  testWidgets('Small-screen does not overflow', (tester) async {
    const smallSize = Size(320, 560); // narrow device
    tester.view.physicalSize = smallSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _ensureAtShell(tester);

    // Ensure bottom nav still renders all five items (icons by key)
    expect(find.byKey(const Key('tab-plan')), findsOneWidget);
    expect(find.byKey(const Key('tab-discover')), findsOneWidget);
    expect(find.byKey(const Key('tab-groups')), findsOneWidget);
    expect(find.byKey(const Key('tab-calendar')), findsOneWidget);
    expect(find.byKey(const Key('tab-messages')), findsOneWidget);
  });
}
