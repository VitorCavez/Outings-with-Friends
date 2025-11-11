// integration_test/outings_deeplink_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:outings_app/main.dart' show OutingsApp;
import 'package:outings_app/routes/app_router.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Deep link to /outings/:id shows details header',
      (WidgetTester tester) async {
    // Pump the app without Firebase to keep the test environment simple.
    await tester.pumpWidget(const OutingsApp(useFirebase: false));

    // Ensure the first frame renders.
    await tester.pump();

    // Navigate directly via the global router to mimic an external deep link.
    AppRouter.router.go('/outings/test-123');

    // Let routing & the first frame of OutingDetails build (skeleton is fine).
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Assert: the details scaffold/app bar is visible.
    expect(find.text('Outing details'), findsOneWidget);
  });
}
