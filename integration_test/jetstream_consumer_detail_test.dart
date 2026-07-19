import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;

import 'helpers/nats_test_app.dart';

/// Exercises `JetStreamManager.consumerDetail()` (Milestone 29) against a
/// real, locally-running JetStream-enabled `nats-server` (see AGENTS.md
/// "Recipe E: Local JetStream Testing").
///
/// The app's own Create Consumer dialog has no fields for `ack_wait`,
/// `max_deliver`, or `max_ack_pending` (and `dart_nats` 1.2.3's
/// `ConsumerConfig` has no fields for them either -- see ROADMAP.md's
/// Milestone 29 entry), so this seeds a consumer with non-default values for
/// all three via a second, direct `dart_nats` client issuing the same raw
/// `$JS.API.CONSUMER.DURABLE.CREATE` request the package's own
/// `createConsumer()` makes internally, just with a hand-built JSON config
/// carrying the extra fields. It then opens that consumer's detail dialog
/// through the real UI and confirms the app's own raw-JSON
/// `consumerDetail()` fetch reads all three back correctly from the real
/// server.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Consumer Detail shows ack-wait/max-deliver/max-ack-pending for a consumer seeded with non-default values',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_cdetail_$runId';
    final consumerName = 'it_consumer_$runId';

    final directClient = Client();
    await directClient.connect(
      Uri.parse(
          '${constants.defaultScheme}${constants.defaultHost}:${constants.defaultPort}'),
    );
    addTearDown(() => directClient.close());

    addTearDown(() async {
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

    // 1. Create the backing stream through the real UI.
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

    // 2. Seed a durable consumer with non-default ack_wait (45s), max_deliver
    // (5), and max_ack_pending (200) via a raw request from a second, direct
    // client -- the same subject/payload shape `JetStream.createConsumer()`
    // builds internally, just with the extra fields the typed `ConsumerConfig`
    // can't express added by hand.
    final createPayload = utf8.encode(jsonEncode({
      'stream_name': streamName,
      'config': {
        'durable_name': consumerName,
        'ack_policy': 'explicit',
        'deliver_policy': 'all',
        'ack_wait': 45 * 1000000000,
        'max_deliver': 5,
        'max_ack_pending': 200,
      },
    }));
    final createResponse = await directClient.request(
      '\$JS.API.CONSUMER.DURABLE.CREATE.$streamName.$consumerName',
      Uint8List.fromList(createPayload),
    );
    final createMap = jsonDecode(createResponse.string) as Map<String, dynamic>;
    expect(createMap['error'], isNull,
        reason: 'raw consumer creation should succeed: $createMap');

    // 3. Back in the app: select the stream, refresh its consumer list, and
    // open the seeded consumer's detail dialog.
    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await pumpUntil(
        tester, () => find.text(consumerName).evaluate().isNotEmpty);
    await tester.tap(find.text(consumerName));
    await tester.pumpAndSettle();

    // 4. The app's own raw-JSON `consumerDetail()` fetch must read the three
    // fields back correctly from the real server.
    expect(find.text('Ack Wait: 45s'), findsOneWidget);
    expect(find.text('Max Deliver: 5'), findsOneWidget);
    expect(find.text('Max Ack Pending: 200'), findsOneWidget);

    // 5. Clean up the consumer explicitly (the stream teardown above would
    // also remove it, but doing it via the UI exercises the same Delete path
    // as `jetstream_lifecycle_test.dart`). The detail dialog opened in step 3
    // is still showing -- its own Delete button pops it and opens the
    // "Delete Consumer?" confirmation, matching `_showConsumerDetail`'s
    // `onDelete` wiring in `jetstream_dashboard.dart`.
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
}
