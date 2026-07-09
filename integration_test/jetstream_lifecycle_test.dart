import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the full JetStream mutation lifecycle (Milestone 1b) against a
/// real, locally-running JetStream-enabled `nats-server` (see AGENTS.md
/// "Recipe E: Local JetStream Testing"): create a stream, publish into it
/// with a delivery ack, create an explicit-ack consumer, tail it and ack a
/// message, then delete the consumer, purge, and delete the stream.
///
/// This is one long ordered scenario rather than several small ones:
/// JetStream stream/consumer objects live on the shared server, not in
/// per-test widget state, so splitting into separate `testWidgets` blocks
/// would only mean re-establishing the same state repeatedly for no real
/// isolation benefit. The stream/consumer names are randomized so a prior
/// run's failed cleanup can't collide with this run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'create stream -> publish with ack -> create consumer -> tail+ack -> delete consumer -> purge -> delete stream',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_orders_$runId';
    final consumerName = 'it_consumer_$runId';
    final ackPayload = 'it-ack-$runId';
    final nakPayload = 'it-nak-$runId';
    final termPayload = 'it-term-$runId';

    Future<void> publishViaJetStream(String subject, String payload) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), subject);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Data'), payload);
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
    }

    /// The tail view lists one row per message, each with its own Ack/Nak/
    /// Term/Copy buttons — scope the lookup to the row containing [payload]
    /// rather than the ambiguous `find.byTooltip(tooltip)` (which matches
    /// every row) once more than one message is on screen.
    ///
    /// Nak specifically causes the *server* to redeliver that message, so a
    /// second row with the same payload can legitimately appear after
    /// nak'ing it — new deliveries are inserted at the top of the list
    /// (`_messages.insert(0, message)`), so `.last` deterministically keeps
    /// referring to the original row we interacted with, however many
    /// redeliveries show up afterward.
    Finder actionButtonFor(String payload, String tooltip) {
      final row = find.ancestor(
          of: find.text(payload).last, matching: find.byType(ListTile));
      final tooltipFinder =
          find.descendant(of: row, matching: find.byTooltip(tooltip));
      return find.ancestor(
          of: tooltipFinder, matching: find.byType(IconButton));
    }

    addTearDown(() async {
      // Best-effort cleanup in case an assertion above failed before the
      // scenario's own delete-stream step ran.
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

    // 1. Switch to the JetStream tab.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();

    // 2. Create a stream.
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
    await tester.pumpAndSettle();
    expect(find.text(streamName), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 3. Switch to Live Messages (Send Message is tab-scoped) and publish
    // three messages into the stream via the JetStream ack checkbox — one
    // each to Ack, Nak, and Term in step 5.
    await tester.tap(find.text('Live Messages'));
    await tester.pumpAndSettle();
    await publishViaJetStream('$streamName.ack', ackPayload);
    await publishViaJetStream('$streamName.nak', nakPayload);
    await publishViaJetStream('$streamName.term', termPayload);

    // 4. Back to JetStream. Note: `JetStreamDashboard`'s state does NOT
    // survive this round trip — this app's `TabBarView` doesn't opt its
    // pages into `AutomaticKeepAliveClientMixin`, so switching tabs
    // disposes and rebuilds it from scratch (confirmed empirically: it
    // re-runs its availability check and stream list load every time), so
    // the stream must be re-selected here rather than assumed still
    // selected.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text(streamName).evaluate().isNotEmpty);
    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Consumer'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Durable Name (optional)'),
        consumerName);
    // Ack Policy defaults to 'Explicit' and Deliver Policy to 'All' — both
    // needed for the tail+ack step below, so no dropdown changes required.
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(
        tester, () => find.text('Consumer created.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(consumerName), findsOneWidget);
    expect(find.textContaining('Ack: explicit'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 5. Tail the consumer and exercise Ack, Nak, and Term — one on each of
    // the three messages published in step 3.
    await tester.tap(find.text(consumerName));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Tail'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text(termPayload).evaluate().isNotEmpty);
    expect(find.text(ackPayload), findsOneWidget);
    expect(find.text(nakPayload), findsOneWidget);

    Future<void> tapActionAndExpectDisabled(String payload, String tooltip,
        {required String reason}) async {
      final buttonFinder = actionButtonFor(payload, tooltip);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(buttonFinder);
      expect(button.onPressed, isNull, reason: reason);
    }

    await tapActionAndExpectDisabled(ackPayload, 'Ack',
        reason: 'Ack/Nak/Term should disable once a message is acked');
    await tapActionAndExpectDisabled(nakPayload, 'Nak (redeliver)',
        reason: 'Ack/Nak/Term should disable once a message is nak\'d');
    await tapActionAndExpectDisabled(termPayload, 'Term (stop redelivery)',
        reason: 'Ack/Nak/Term should disable once a message is terminated');

    // 6. Delete the consumer.
    await tester.tap(find.byTooltip('Back to stream details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete consumer'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Consumer?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(
        tester,
        () => find
            .text('Consumer "$consumerName" deleted.')
            .evaluate()
            .isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(consumerName), findsNothing);
    await waitForSnackBarGone(tester);

    // 7. Purge the stream.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
    await tester.pumpAndSettle();
    expect(find.text('Purge Stream?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" purged.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    // 8. Delete the stream.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Stream'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Stream?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Select a stream to see details.'), findsOneWidget);
    expect(find.text(streamName), findsNothing);
  });
}
