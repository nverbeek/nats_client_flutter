import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the JetStream "Browse Messages" view (`JetStreamMessageView`,
/// the ephemeral ordered-consumer tail) against a real, locally-running
/// JetStream-enabled `nats-server` (see AGENTS.md "Recipe E: Local
/// JetStream Testing"). This view was flagged untestable-via-fake back in
/// Milestone 1a (an `OrderedConsumer` is bound to a real `Client`) and was
/// still unexercised even after the real-server integration suite landed —
/// `jetstream_lifecycle_test.dart` tails a named consumer instead of using
/// this button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Browse Messages shows published messages and its row menu works',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_browse_$runId';
    final payload = 'it-browse-payload-$runId';

    addTearDown(() async {
      // Best-effort cleanup in case an assertion above failed first.
      final leftoverStream = find.text(streamName);
      if (leftoverStream.evaluate().isEmpty) return;
      await tester.tap(leftoverStream);
      await tester.pumpAndSettle();
      final deleteStreamButton =
          find.widgetWithText(OutlinedButton, 'Delete Stream');
      if (deleteStreamButton.evaluate().isEmpty) return;
      await tester.tap(deleteStreamButton);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Delete');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.last);
        await tester.pumpAndSettle();
      }
    });

    // 1. Create a stream.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Stream'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), streamName);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        '$streamName.>');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" created.').evaluate().isNotEmpty);
    await waitForSnackBarGone(tester);

    // 2. Publish a message into it via the Live Messages tab.
    await tester.tap(find.text('Live Messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'), '$streamName.created');
    await tester.enterText(find.widgetWithText(TextFormField, 'Data'), payload);
    await tester.tap(find.text('Publish via JetStream (get delivery ack)'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await pumpUntil(
        tester,
        () => find
            .textContaining('Published to stream "$streamName" at seq')
            .evaluate()
            .isNotEmpty);
    await waitForSnackBarGone(tester);

    // 3. Back to JetStream (re-select — dashboard state doesn't survive the
    // tab round trip, see jetstream_lifecycle_test.dart), then Browse.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text(streamName).evaluate().isNotEmpty);
    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Browse Messages'));
    await tester.pumpAndSettle();

    await pumpUntil(tester, () => find.text(payload).evaluate().isNotEmpty);
    expect(find.textContaining('Browsing: $streamName'), findsOneWidget);

    // 4. Row menu: Detail opens the Message Detail dialog.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Message Detail'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // 5. Row menu: Copy copies the payload to the clipboard.
    final copiedData = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copiedData, contains(payload));

    // 6. Back to stream details, then clean up.
    await tester.tap(find.byTooltip('Back to stream details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Stream'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(
        tester,
        () =>
            find.text('Stream "$streamName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(streamName), findsNothing);
  });
}
