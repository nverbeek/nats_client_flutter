import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/object_store_manager.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the full Object Store lifecycle (Milestone 7) against a real,
/// locally-running JetStream-enabled `nats-server` (see AGENTS.md "Recipe
/// E: Local JetStream Testing" — Object Store buckets are backed by
/// JetStream streams just like KV, so no separate fixture server is needed):
/// create a bucket through the UI, upload and download objects, confirm the
/// dashboard's explicit Refresh (there is no `watch()` for Object Store,
/// unlike KV) picks up an object written by a second, direct client, verify
/// downloaded bytes match byte-for-byte, then delete an object and the
/// bucket through the UI.
///
/// Upload/Download themselves go through a native OS file picker
/// (`file_picker`'s `pickFiles()`/`saveFile()`), which — like the TLS cert
/// "Browse" buttons in `security_settings_dialog_test.dart` — isn't
/// meaningfully driveable from an automated test. `ObjectStoreDashboard`'s
/// `pickUploadFile`/`saveDownloadedFile` injection points are covered
/// directly by `test/object_store_dashboard_test.dart` instead. Here, the
/// equivalent data-path calls go straight through a second
/// [ObjectStoreManager] bound to a second, direct `dart_nats` client —
/// exercising the exact same `ObjectStore.put()`/`getBytes()` calls the real
/// UI buttons would invoke, against the real server, just without the
/// native file dialog in between. Every other step (bucket create/delete,
/// object list, Refresh, object delete) goes through the real UI.
///
/// One long ordered scenario rather than several small ones, mirroring
/// `kv_lifecycle_test.dart`: the bucket/objects live on the shared server,
/// not per-test widget state. The bucket name is randomized so a prior run's
/// failed cleanup can't collide with this run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A prior run's failed cleanup (or an unrelated bucket on the shared
  // server) can leave other buckets in the list, each with their own
  // "Delete bucket" tooltip — scope to the row for the specific bucket
  // rather than the ambiguous unscoped `find.byTooltip('Delete bucket')`.
  Finder bucketDeleteButton(String bucket) => find.descendant(
      of: find.ancestor(of: find.text(bucket), matching: find.byType(ListTile)),
      matching: find.byTooltip('Delete bucket'));

  testWidgets(
      'create bucket -> live external upload appears after Refresh -> download matches byte-for-byte -> delete object -> delete bucket',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final bucketName = 'it_objstore_$runId';
    const objectName = 'report.bin';

    final directClient = Client();
    await directClient.connect(
      Uri.parse(
          '${constants.defaultScheme}${constants.defaultHost}:${constants.defaultPort}'),
    );
    addTearDown(() => directClient.close());
    final directManager = ObjectStoreManager(directClient);

    addTearDown(() async {
      // Best-effort cleanup in case an assertion above failed before the
      // scenario's own delete-bucket step ran.
      final leftoverBucket = find.text(bucketName);
      if (leftoverBucket.evaluate().isEmpty) return;
      await tester.tap(bucketDeleteButton(bucketName));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Delete');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.last);
        await tester.pumpAndSettle();
      }
    });

    // 1. Switch to the Object Store tab.
    await tester.tap(find.text('Object Store'));
    await tester.pumpAndSettle();

    // 2. Create a bucket.
    await tester.tap(find.text('Create Bucket'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), bucketName);
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(tester,
        () => find.text('Bucket "$bucketName" created.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(bucketName), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 3. Select the bucket. It starts empty.
    await tester.tap(find.text(bucketName));
    await tester.pumpAndSettle();
    expect(find.text('No objects in this bucket yet.'), findsOneWidget);

    // 4. A second, direct dart_nats client uploads an object spanning
    // multiple chunks (> 128 KiB), straight into the bucket — this must
    // *not* appear until Refresh is tapped, since Object Store has no
    // watch() equivalent (unlike KV's live updates).
    final uploadedBytes =
        Uint8List.fromList(List<int>.generate(300 * 1024, (i) => i % 256));
    final putInfo =
        await directManager.putObject(bucketName, objectName, uploadedBytes);
    expect(putInfo.chunks, greaterThan(1));

    // Give the server a moment, then confirm the UI still shows the old
    // (empty) state without an explicit refresh.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(objectName), findsNothing);

    // 5. Tapping Refresh objects picks up the externally-written object.
    await tester.tap(find.byTooltip('Refresh objects'));
    await pumpUntil(tester, () => find.text(objectName).evaluate().isNotEmpty);
    expect(find.textContaining('300.0 KB'), findsOneWidget);
    expect(find.textContaining('3 chunks'), findsOneWidget);

    // 6. Download (via the same manager class the UI's Download button
    // uses — see the file-level doc comment for why this bypasses the
    // native save-file dialog) and verify the bytes match exactly,
    // confirming chunk reassembly and the SHA-256 digest check both work
    // end-to-end against a real server.
    final downloaded = await directManager.getObject(bucketName, objectName);
    expect(downloaded, isNotNull);
    expect(downloaded, orderedEquals(uploadedBytes));

    // 7. Delete the object through the UI.
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Object?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(tester,
        () => find.text('Object "$objectName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(objectName), findsNothing);
    await waitForSnackBarGone(tester);

    // Confirm the delete really reached the server, not just the local list.
    final afterDelete = await directManager.getObject(bucketName, objectName);
    expect(afterDelete, isNull);

    // 8. Delete the bucket.
    await tester.tap(bucketDeleteButton(bucketName));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bucket?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(tester,
        () => find.text('Bucket "$bucketName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Select a bucket to see its objects.'), findsOneWidget);
    expect(find.text(bucketName), findsNothing);
  });
}
