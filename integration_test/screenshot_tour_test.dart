import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;

import 'helpers/nats_test_app.dart';
import 'helpers/screenshot_signal.dart';

/// Drives the real app through the screens featured in the main README's
/// "Screenshots" section, asking `scripts/capture_screenshots.ps1` (see
/// `helpers/screenshot_signal.dart` for why that has to be a separate
/// process) to capture each one. This turns "re-take the README
/// screenshots after a UI change" into a single command instead of a
/// manual re-take/crop/round-corner pass.
///
/// Do not run this file directly with `flutter test` — it needs a
/// JetStream-enabled `nats-server` seeded in lockstep with the checkpoints
/// below, and nothing will ever answer its capture requests. Run
/// `pwsh ./scripts/capture_screenshots.ps1` instead, which sets both up.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture README screenshots', (tester) async {
    final signaler = ScreenshotSignaler();

    // Fix the window's size/position so screenshots come out at the same
    // resolution every run, regardless of whatever this machine's app last
    // remembered from a previous manual session.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(constants.prefLastWidth, 1600);
    await prefs.setDouble(constants.prefLastHeight, 1000);
    await prefs.setDouble(constants.prefLastPositionX, 60);
    await prefs.setDouble(constants.prefLastPositionY, 60);

    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    Finder fieldWithPrefixIcon(IconData icon) => find.ancestor(
        of: find.byIcon(icon), matching: find.byType(TextFormField));

    // 1. Messages: the orchestrator publishes the sample car/animal
    // payloads (`scripts/message_pub.ps1`) now that the app is connected
    // and subscribed, then this waits for all 5 to arrive before capturing.
    await signaler.requestSeedMessages();
    await pumpUntil(tester,
        () => find.textContaining('Total Messages: 5,').evaluate().isNotEmpty);
    await signaler.capture(tester, 'Messages');

    // 2. Filter and Sort: narrow to the animal.* messages and highlight
    // "family" within them.
    await tester.enterText(fieldWithPrefixIcon(Icons.filter_list), 'animal');
    await tester.enterText(fieldWithPrefixIcon(Icons.search), 'family');
    await tester.pump();
    await signaler.capture(tester, 'Filter and Sort');

    // 3. Message Detail: clear the filter/find, then open the Bengal Tiger
    // (`animal.tiger`) row's Detail dialog.
    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.filter_list),
        matching: find.byIcon(Icons.clear)));
    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.search),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();

    final tigerRow = find.ancestor(
        of: find.text('animal.tiger'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: tigerRow, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    await signaler.capture(tester, 'Message Detail');
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // 4. JetStream: select the "orders" stream seeded by
    // `scripts/jetstream_demo.ps1` and create a consumer so the dashboard
    // shows real stream + consumer stats rather than an empty state.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text('orders').evaluate().isNotEmpty);
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Consumer'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Durable Name (optional)'),
        'dashboard-demo');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(
        tester, () => find.text('Consumer created.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);
    await signaler.capture(tester, 'JetStream');
  });
}
