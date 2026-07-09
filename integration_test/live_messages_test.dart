import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the core NATS publish/subscribe round trip against a real,
/// locally-running `nats-server` (see AGENTS.md "Recipe E: Local JetStream
/// Testing" for how to start one — this test only needs plain NATS, no
/// `-js` flag required, though it's harmless if JetStream is enabled too).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sending a message shows it in the Live Messages list',
      (tester) async {
    // Default subscribed subject is '>' (see constants.defaultSubject), so
    // the app receives its own publish — a full publish -> subscribe -> UI
    // round trip through the real server.
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final uniqueSubject =
        'integration.smoke.${DateTime.now().microsecondsSinceEpoch}';
    final uniquePayload =
        'integration-test-payload-${DateTime.now().microsecondsSinceEpoch}';

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'), uniqueSubject);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Data'), uniquePayload);

    await tester.tap(find.widgetWithText(TextButton, 'Send'));

    await pumpUntil(
      tester,
      () => find.text(uniquePayload).evaluate().isNotEmpty,
    );

    expect(find.text(uniquePayload), findsOneWidget);
  });
}
