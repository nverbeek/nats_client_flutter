import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;

import 'helpers/nats_test_app.dart';

/// Exercises the Milestone 27 Edit Stream flow -- `JetStreamManager
/// .streamDetail()`/`updateStream()` and `StreamConfigDialog`'s edit mode --
/// against a real, locally-running JetStream-enabled `nats-server` (see
/// AGENTS.md "Recipe E: Local JetStream Testing").
///
/// Deliberately doesn't touch Storage or Retention Policy: `nats-server`
/// rejects in-place changes to those two on some/all server versions, and
/// this test isn't trying to pin down that server-version-dependent
/// behavior -- a rejection would surface through the same
/// `describeJetStreamError`-backed error SnackBar already covered by
/// `jetstream_dashboard_test.dart`'s "a mutation failure shows an error
/// SnackBar" test. This exercises fields NATS does allow updating in place:
/// max age, max messages, discard policy, and the deny-purge flag.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Edit Stream pre-fills from a fresh streamDetail() fetch and updateStream() reflects server-side',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_stream_edit_$runId';

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

    // 1. Create the stream through the real UI with defaults (no max age,
    // no max msgs, default 'old' discard, deny_purge unset).
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

    // 2. Open the stream and use Edit -- this round-trips through the app's
    // own `streamDetail()` fetch to pre-fill the dialog.
    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Stream'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max Age (days, optional)'), '3');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max Messages (optional)'), '50');
    // The dropdown's pre-filled label reads "Old", not "Default" -- a real
    // server always echoes an explicit `discard: "old"` in a freshly created
    // stream's config (confirmed via a direct `$JS.API.STREAM.CREATE`
    // request), it never actually omits the field to mean "default".
    await tester.tap(find.text('Old'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').last);
    await tester.pumpAndSettle();
    // The dialog's content area is a fixed-height scrollable -- with Max Age
    // and Max Messages now filled in above it, Deny Purge can sit scrolled
    // out of the test viewport, so a plain tap() misses (hit-test warning,
    // switch silently doesn't flip) unless it's scrolled into view first.
    final denyPurgeSwitch = find.widgetWithText(SwitchListTile, 'Deny Purge');
    await tester.ensureVisible(denyPurgeSwitch);
    await tester.pumpAndSettle();
    await tester.tap(denyPurgeSwitch);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" updated.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    // 3. Confirm the real server actually reflects the new config, not just
    // the app's own local state -- a second, direct client re-fetches
    // `$JS.API.STREAM.INFO.<stream>` independently of the app under test.
    final infoResponse = await directClient.request(
      '\$JS.API.STREAM.INFO.$streamName',
      Uint8List(0),
    );
    final infoMap = jsonDecode(infoResponse.string) as Map<String, dynamic>;
    final cfg = infoMap['config'] as Map<String, dynamic>;
    expect(cfg['max_age'], 3 * Duration.microsecondsPerDay * 1000);
    expect(cfg['max_msgs'], 50);
    expect(cfg['discard'], 'new');
    expect(cfg['deny_purge'], isTrue);

    // 4. Reopening Edit should show the same values -- confirming the app's
    // own `streamDetail()` fetch reads them back correctly too, not just
    // the direct client.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });
}
