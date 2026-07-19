import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Exercises `KvManager.bucketStatus()` (Milestone 29) against a real,
/// locally-running JetStream-enabled `nats-server` (see AGENTS.md "Recipe E:
/// Local JetStream Testing"): creates a bucket with a non-default TTL and
/// history depth through the normal Create Bucket dialog, then confirms the
/// Bucket Info dialog's raw `$JS.API.STREAM.INFO` request correctly reads
/// back `max_age` (TTL) and `max_msgs_per_subject` (history) from the real
/// server -- the two fields `dart_nats` 1.2.3's own `KeyValue.status()`
/// can't surface at all (see ROADMAP.md's Milestone 29 entry).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Bucket Info reflects a non-default TTL/history/storage set at creation',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final bucketName = 'it_kvinfo_$runId';

    addTearDown(() async {
      final leftoverBucket = find.text(bucketName);
      if (leftoverBucket.evaluate().isEmpty) return;
      await tester.tap(find.byTooltip('Delete bucket'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Delete');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.last);
        await tester.pumpAndSettle();
      }
    });

    // 1. Switch to the Key-Value Stores tab and create a bucket with a
    // non-default TTL (7 days) and history depth (4).
    await tester.tap(find.text('Key-Value Stores'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Bucket'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), bucketName);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'History Depth'), '4');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'TTL (days, optional)'), '7');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(tester,
        () => find.text('Bucket "$bucketName" created.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await waitForSnackBarGone(tester);

    // 2. Select the bucket and open its Bucket Info dialog.
    await tester.tap(find.text(bucketName));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bucket info'));
    await tester.pumpAndSettle();

    // 3. The raw-JSON `bucketStatus()` fetch must correctly read back what
    // was actually set server-side -- not just echo back the dialog's own
    // input, since this specifically exercises the real wire response.
    expect(find.text('Bucket Info: $bucketName'), findsOneWidget);
    expect(find.text('Storage: file'), findsOneWidget);
    expect(find.text('History Depth: 4'), findsOneWidget);
    expect(find.text('TTL: 7 days'), findsOneWidget);
    expect(find.text('Replicas: 1'), findsOneWidget);
    expect(find.text('Values: 0'), findsOneWidget);
  });
}
