import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the two app-side follow-ups to ROADMAP.md Milestone 30 that
/// touch existing JetStream UI -- consumer Pause/Resume and filtered/keep
/// stream purge -- against a real, locally-running JetStream-enabled
/// `nats-server` (see AGENTS.md "Recipe E: Local JetStream Testing"). Both
/// capabilities require `dart_nats` 1.4.0 (pause/resume shipped in 1.3.0,
/// filtered/keep purge in 1.4.0) and a NATS server new enough to support the
/// consumer pause API (2.11+).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Pause/Resume a durable pull consumer via Consumer Detail',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_pause_$runId';
    final consumerName = 'it_pause_consumer_$runId';

    addTearDown(() async {
      final leftoverStream = find.text(streamName);
      if (leftoverStream.evaluate().isEmpty) return;
      await tester.tap(leftoverStream.first);
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

    // 1. Create the stream and a durable pull consumer through the real UI.
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
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Consumer'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Durable Name (optional)'),
        consumerName);
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(
        tester, () => find.text('Consumer created.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    // 2. Open its detail dialog and pause it for a short duration.
    await pumpUntil(
        tester, () => find.text(consumerName).evaluate().isNotEmpty);
    await tester.tap(find.text(consumerName));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Pause'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Pause "$consumerName"?'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Pause for how many minutes'),
        '1');
    await tester.tap(find.widgetWithText(TextButton, 'Pause').last);
    await pumpUntil(
        tester, () => find.textContaining('Paused until:').evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    // 3. Resume it immediately and confirm the paused state clears.
    expect(find.widgetWithText(TextButton, 'Resume'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await pumpUntil(tester,
        () => find.textContaining('Paused until:').evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Pause'), findsOneWidget);

    // 4. Clean up the consumer via the dialog's own Delete action.
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
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
    await waitForSnackBarGone(tester);
  });

  testWidgets(
      'Purge Stream with a subject filter only removes matching messages, '
      'and Keep Newest retains the newest N', (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_purge_$runId';

    addTearDown(() async {
      final leftoverStream = find.text(streamName);
      if (leftoverStream.evaluate().isEmpty) return;
      await tester.tap(leftoverStream.first);
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

    // 1. Create the stream through the real UI.
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
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    // 2. Send Message is Live Messages-tab-scoped (same constraint as
    // `jetstream_lifecycle_test.dart`) -- switch there to publish 3 messages
    // on ".a" and 2 on ".b" (5 total), then switch back. `JetStreamDashboard`
    // doesn't survive a tab round trip (no `AutomaticKeepAliveClientMixin`),
    // so the stream must be re-selected afterward rather than assumed still
    // selected.
    await tester.tap(find.text('Live Messages'));
    await tester.pumpAndSettle();
    await publishViaJetStream('$streamName.a', 'msg-a-1');
    await publishViaJetStream('$streamName.a', 'msg-a-2');
    await publishViaJetStream('$streamName.a', 'msg-a-3');
    await publishViaJetStream('$streamName.b', 'msg-b-1');
    await publishViaJetStream('$streamName.b', 'msg-b-2');

    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text(streamName).evaluate().isNotEmpty);
    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await pumpUntil(
        tester, () => find.textContaining('Messages: 5').evaluate().isNotEmpty);

    // 3. Purge with a subject filter restricted to ".a" -- only those 3
    // should go, leaving the 2 ".b" messages.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject Filter (optional)'),
        '$streamName.a');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" purged.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);
    await pumpUntil(
        tester, () => find.textContaining('Messages: 2').evaluate().isNotEmpty);

    // 4. Purge with Keep Newest = 1 (no filter) -- only the newest of the
    // remaining 2 messages should survive.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Newest'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Keep newest N messages'), '1');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" purged.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);
    await pumpUntil(
        tester, () => find.textContaining('Messages: 1').evaluate().isNotEmpty);

    // 5. Clean up: default all-scope purge, then delete the stream.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" purged.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Stream'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  });
}
