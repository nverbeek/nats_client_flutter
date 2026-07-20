import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/kv_put_dialog.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the full Key-Value mutation lifecycle (Milestone 2) against a
/// real, locally-running JetStream-enabled `nats-server` (see AGENTS.md
/// "Recipe E: Local JetStream Testing"): create a bucket, put a value,
/// confirm a change made by a second, direct `dart_nats` client shows up
/// live via `KvManager.watch()` with no manual refresh, edit a key through
/// the UI, exercise the optimistic-concurrency conflict path (a stale edit
/// must be rejected, not silently overwrite someone else's change), check
/// History, then delete a key, purge a key, and delete the bucket.
///
/// One long ordered scenario rather than several small ones, mirroring
/// `jetstream_lifecycle_test.dart`: the bucket/keys live on the shared
/// server, not per-test widget state, so splitting into separate
/// `testWidgets` blocks would only mean re-establishing the same state
/// repeatedly for no real isolation benefit. The bucket name is randomized
/// so a prior run's failed cleanup can't collide with this run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The connection bar's Host/Port/Subjects fields are also `TextFormField`s
  // and remain mounted (just disabled) while the Put/Edit dialog is open, so
  // an unscoped `find.byType(TextFormField).at(n)` would silently target the
  // wrong field. Scope to the dialog explicitly instead.
  Finder putDialogField(int index) => find
      .descendant(
          of: find.byType(KvPutValueDialog),
          matching: find.byType(TextFormField))
      .at(index);

  // A prior run's failed cleanup (or an unrelated bucket on the shared
  // server) can leave other buckets in the list, each with their own
  // "Delete bucket" tooltip — scope to the row for the specific bucket
  // rather than the ambiguous unscoped `find.byTooltip('Delete bucket')`.
  Finder bucketDeleteButton(String bucket) => find.descendant(
      of: find.ancestor(of: find.text(bucket), matching: find.byType(ListTile)),
      matching: find.byTooltip('Delete bucket'));

  testWidgets(
      'create bucket -> put -> live external update -> edit -> stale-edit conflict -> history -> delete key -> purge key -> delete bucket',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final bucketName = 'it_kv_$runId';

    final directClient = Client();
    await directClient.connect(
      Uri.parse(
          '${constants.defaultScheme}${constants.defaultHost}:${constants.defaultPort}'),
    );
    addTearDown(() => directClient.close());
    final directKv =
        await directClient.jetStream().keyValue(bucketName, create: false);

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

    // 1. Switch to the Key-Value Stores tab.
    await tester.tap(find.text('Key-Value Stores'));
    await tester.pumpAndSettle();

    // 2. Create a bucket.
    await tester.tap(find.text('Create Bucket'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), bucketName);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'History Depth'), '5');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(tester,
        () => find.text('Bucket "$bucketName" created.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(bucketName), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 3. Select the bucket and put a value.
    await tester.tap(find.text(bucketName));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Put Value'));
    await tester.pumpAndSettle();
    await tester.enterText(putDialogField(0), 'db.port');
    await tester.enterText(putDialogField(1), '5432');
    await tester.tap(find.widgetWithText(TextButton, 'Put'));
    await pumpUntil(
        tester, () => find.text('Key "db.port" saved.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('db.port'), findsOneWidget);
    expect(find.textContaining('5432'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 4. A second, direct dart_nats client puts a *different* key straight
    // into the bucket — this must show up live via KvManager.watch(), with
    // no manual refresh, since the app never called putValue() itself.
    await directKv.putString('feature.enabled', 'true');
    await pumpUntil(
        tester, () => find.text('feature.enabled').evaluate().isNotEmpty);
    expect(find.textContaining('true'), findsOneWidget);

    // 5. Edit "db.port" through the UI.
    await tester.tap(find.text('db.port'));
    await tester.pumpAndSettle();
    await tester.enterText(putDialogField(1), '5433');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester,
        () => find.text('Key "db.port" updated.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.textContaining('5433'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 6. Stale-edit conflict: open the Edit dialog (captures the current
    // revision), then have the direct client change the same key *while
    // the dialog is still open*, then try to Save — the optimistic-
    // concurrency check must reject it rather than silently clobber the
    // external change. Like every other dialog in this app (e.g. Create
    // Stream), Save pops the dialog immediately and the mutation runs async
    // in the background, surfacing success/failure via a snackbar
    // afterward — so there's no dialog left to Cancel out of here.
    await tester.tap(find.text('db.port'));
    await tester.pumpAndSettle();
    await directKv.putString('db.port', '5555');
    await tester.enterText(putDialogField(1), '5434');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(
        tester,
        () => find
            .textContaining(
                'This key changed since it was loaded — reload and try again.')
            .evaluate()
            .isNotEmpty);
    await waitForSnackBarGone(tester);
    // The external client's write (5555) should still have reached the UI
    // live, since watch() doesn't care who made the change.
    await pumpUntil(
        tester, () => find.textContaining('5555').evaluate().isNotEmpty);

    // 7. History shows both past revisions.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    expect(find.text('History: db.port'), findsOneWidget);
    expect(find.textContaining('Rev #'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // 8. Delete "feature.enabled".
    final featureRow = find.ancestor(
        of: find.text('feature.enabled'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: featureRow, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete Key?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(
        tester,
        () =>
            find.text('Key "feature.enabled" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('feature.enabled'), findsNothing);
    await waitForSnackBarGone(tester);

    // 9. Purge "db.port".
    final portRow = find.ancestor(
        of: find.text('db.port'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: portRow, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purge').last);
    await tester.pumpAndSettle();
    expect(find.text('Purge Key?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await pumpUntil(
        tester, () => find.text('Key "db.port" purged.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('db.port'), findsNothing);
    await waitForSnackBarGone(tester);

    // 10. Delete the bucket.
    await tester.tap(bucketDeleteButton(bucketName));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bucket?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(tester,
        () => find.text('Bucket "$bucketName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Select a bucket to see its keys.'), findsOneWidget);
    expect(find.text(bucketName), findsNothing);
  });
}
