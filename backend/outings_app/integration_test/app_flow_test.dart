@TestOn('!windows')
// integration_test/app_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// App entry
import 'package:outings_app/main.dart' as app;
// Router (so we can jump past the splash screen)
import 'package:outings_app/routes/app_router.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App shell + tab navigation', () {
    testWidgets('Launches and shows bottom tabs', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Jump to the home shell to ensure bottom nav is visible
      AppRouter.router.go('/home');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Find tabs by keys (robust regardless of labels/platform)
      expect(find.byKey(const Key('tab-plan')), findsOneWidget);
      expect(find.byKey(const Key('tab-discover')), findsOneWidget);
      expect(find.byKey(const Key('tab-groups')), findsOneWidget);
      expect(find.byKey(const Key('tab-calendar')), findsOneWidget);
      expect(find.byKey(const Key('tab-messages')), findsOneWidget);
    });

    testWidgets('Can switch between all tabs', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Ensure we start on the shell with bottom nav
      AppRouter.router.go('/home');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      Future<void> tapTabAndReturnHome(Key key) async {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget, reason: 'Tab "$key" should be visible');
        await tester.tap(finder);
        await tester.pumpAndSettle(const Duration(milliseconds: 600));

        // Your tab onTap navigates away from the shell (e.g., to /discover),
        // which removes the bottom nav. Jump back to /home for the next tap.
        AppRouter.router.go('/home');
        await tester.pumpAndSettle(const Duration(milliseconds: 600));
      }

      await tapTabAndReturnHome(const Key('tab-discover'));
      await tapTabAndReturnHome(const Key('tab-groups'));
      await tapTabAndReturnHome(const Key('tab-calendar'));
      await tapTabAndReturnHome(const Key('tab-messages'));
      await tapTabAndReturnHome(const Key('tab-plan')); // back to start
    });
  });
}
