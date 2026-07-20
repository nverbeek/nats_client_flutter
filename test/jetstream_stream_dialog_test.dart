import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_stream_dialog.dart';

void main() {
  Widget buildDialog(void Function(StreamConfig) onSubmit,
      {StreamConfig? initial}) {
    return MaterialApp(
      home: Scaffold(
        body: StreamConfigDialog(initial: initial, onSubmit: onSubmit),
      ),
    );
  }

  testWidgets('shows a validation error and blocks submit for an empty name',
      (tester) async {
    var created = false;
    await tester.pumpWidget(buildDialog((_) => created = true));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.>');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(created, isFalse);
    expect(find.text('A stream name is required.'), findsOneWidget);
  });

  testWidgets('shows a validation error and blocks submit for empty subjects',
      (tester) async {
    var created = false;
    await tester.pumpWidget(buildDialog((_) => created = true));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(created, isFalse);
    expect(find.text('At least one subject is required.'), findsOneWidget);
  });

  testWidgets('Create calls onSubmit with the expected StreamConfig',
      (tester) async {
    StreamConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.created, orders.updated');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config, isNotNull);
    expect(config!.name, 'orders');
    expect(config!.subjects, ['orders.created', 'orders.updated']);
    expect(config!.numReplicas, 1);
    expect(config!.maxAge, isNull);
    expect(config!.storage, 'file');
    expect(config!.retention, 'limits');
    expect(config!.discard, isNull);
    expect(config!.maxMsgs, -1);
    expect(config!.maxBytes, -1);
    expect(config!.maxMsgSize, isNull);
    expect(config!.maxMsgsPerSubject, isNull);
    expect(config!.allowRollup, isFalse);
    expect(config!.denyDelete, isFalse);
    expect(config!.denyPurge, isFalse);
  });

  testWidgets('a Max Age value is converted to a Duration in days',
      (tester) async {
    StreamConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.>');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max Age (days, optional)'), '7');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config!.maxAge, const Duration(days: 7));
  });

  testWidgets('selecting a Replicas value passes it through', (tester) async {
    // The dialog's content now overflows the default 800x600 test surface --
    // resize it (matching `security_settings_dialog_test.dart`'s pattern for
    // its own tall dialog) so fields below the fold are actually
    // hit-testable rather than just present-but-unreachable in the tree.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    StreamConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.>');

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config!.numReplicas, 3);
  });

  testWidgets(
      'storage, retention, discard, size limits and flags are submitted',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    StreamConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.>');

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Limits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work Queue').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max Messages (optional)'), '1000');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max Bytes (optional)'), '2048');
    await tester.enterText(
        find.widgetWithText(
            TextFormField, 'Max Message Size (bytes, optional)'),
        '512');
    await tester.enterText(
        find.widgetWithText(
            TextFormField, 'Max Messages Per Subject (optional)'),
        '5');

    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Allow Rollup Headers'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Deny Delete'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Deny Purge'));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config!.storage, 'memory');
    expect(config!.retention, 'workqueue');
    expect(config!.discard, 'new');
    expect(config!.maxMsgs, 1000);
    expect(config!.maxBytes, 2048);
    expect(config!.maxMsgSize, 512);
    expect(config!.maxMsgsPerSubject, 5);
    expect(config!.allowRollup, isTrue);
    expect(config!.denyDelete, isTrue);
    expect(config!.denyPurge, isTrue);
  });

  testWidgets('Cancel does not call onSubmit', (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) =>
                    StreamConfigDialog(onSubmit: (_) => created = true),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(created, isFalse);
    expect(find.byType(StreamConfigDialog), findsNothing);
  });

  group('edit mode', () {
    final existing = StreamConfig(
      name: 'orders',
      subjects: ['orders.created', 'orders.updated'],
      storage: 'memory',
      retention: 'workqueue',
      maxMsgs: 100,
      maxBytes: 4096,
      maxMsgSize: 256,
      maxMsgsPerSubject: 7,
      discard: 'new',
      maxAge: const Duration(days: 5),
      numReplicas: 3,
      allowRollup: true,
      denyDelete: true,
      denyPurge: false,
    );

    testWidgets('pre-fills the form from initial and disables the name field',
        (tester) async {
      await tester.pumpWidget(buildDialog((_) {}, initial: existing));

      expect(find.text('Edit Stream'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
      expect(find.text('orders.created, orders.updated'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('4096'), findsOneWidget);
      expect(find.text('256'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      final nameField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Stream Name'));
      expect(nameField.enabled, isFalse);

      final storageDropdown = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>).first);
      expect(storageDropdown.initialValue, 'memory');

      final replicasDropdown = tester.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>));
      expect(replicasDropdown.initialValue, 3);

      final allowRollupSwitch = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Allow Rollup Headers'));
      expect(allowRollupSwitch.value, isTrue);
      final denyDeleteSwitch = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Deny Delete'));
      expect(denyDeleteSwitch.value, isTrue);
      final denyPurgeSwitch = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Deny Purge'));
      expect(denyPurgeSwitch.value, isFalse);

      expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
    });

    testWidgets('submitting without changes round-trips the same config',
        (tester) async {
      StreamConfig? config;
      await tester
          .pumpWidget(buildDialog((c) => config = c, initial: existing));

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(config, isNotNull);
      expect(config!.name, existing.name);
      expect(config!.subjects, existing.subjects);
      expect(config!.storage, existing.storage);
      expect(config!.retention, existing.retention);
      expect(config!.maxMsgs, existing.maxMsgs);
      expect(config!.maxBytes, existing.maxBytes);
      expect(config!.maxMsgSize, existing.maxMsgSize);
      expect(config!.maxMsgsPerSubject, existing.maxMsgsPerSubject);
      expect(config!.discard, existing.discard);
      expect(config!.maxAge, existing.maxAge);
      expect(config!.numReplicas, existing.numReplicas);
      expect(config!.allowRollup, isTrue);
      expect(config!.denyDelete, isTrue);
      expect(config!.denyPurge, isFalse);
    });

    testWidgets('the stream name cannot be edited even if attempted',
        (tester) async {
      StreamConfig? config;
      await tester
          .pumpWidget(buildDialog((c) => config = c, initial: existing));

      // The field is disabled, but the submitted name should still be
      // whatever `initial` carried, not whatever the (ignored) controller
      // holds -- this guards the `widget.isEdit` branch in `_submit`.
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(config!.name, 'orders');
    });

    testWidgets('preserves allowDirect, which the form does not expose',
        (tester) async {
      // `$JS.API.STREAM.UPDATE` replaces the whole config rather than
      // merging it, so a field this form doesn't render still has to be
      // carried over. KV buckets' backing streams are created with
      // allowDirect: true, so dropping it turned direct gets off for a
      // bucket on an otherwise no-op Edit + Save.
      final kvBacking = StreamConfig(
        name: 'KV_settings',
        subjects: [r'$KV.settings.>'],
        maxMsgsPerSubject: 5,
        allowRollup: true,
        denyDelete: true,
        discard: 'new',
        allowDirect: true,
      );

      StreamConfig? config;
      await tester
          .pumpWidget(buildDialog((c) => config = c, initial: kvBacking));

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(config!.allowDirect, isTrue);
    });

    testWidgets('round-trips a sub-day maxAge instead of clearing it',
        (tester) async {
      // Displayed rounded up to 1 day (the field is whole days), but an
      // untouched field must submit the original Duration -- `inDays` on a
      // 6-hour age truncates to 0, which used to read back as "blank /
      // unlimited" and silently removed the retention window.
      final sixHours = StreamConfig(
        name: 'events',
        subjects: ['events.>'],
        maxAge: const Duration(hours: 6),
      );

      StreamConfig? config;
      await tester
          .pumpWidget(buildDialog((c) => config = c, initial: sixHours));

      expect(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Max Age (days, optional)'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(config!.maxAge, const Duration(hours: 6));
    });

    testWidgets('an edited maxAge submits the newly entered value',
        (tester) async {
      final sixHours = StreamConfig(
        name: 'events',
        subjects: ['events.>'],
        maxAge: const Duration(hours: 6),
      );

      StreamConfig? config;
      await tester
          .pumpWidget(buildDialog((c) => config = c, initial: sixHours));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Max Age (days, optional)'), '3');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(config!.maxAge, const Duration(days: 3));
    });

    testWidgets('shows unlimited (-1) size limits as blank, not as "-1"',
        (tester) async {
      final unlimited = StreamConfig(
        name: 'events',
        subjects: ['events.>'],
        maxMsgSize: -1,
        maxMsgsPerSubject: -1,
      );

      await tester.pumpWidget(buildDialog((_) {}, initial: unlimited));

      expect(find.text('-1'), findsNothing);
    });

    testWidgets(
        'blocks submit on unparseable numeric input instead of '
        'silently wiping the limit', (tester) async {
      var submitted = false;
      await tester
          .pumpWidget(buildDialog((_) => submitted = true, initial: existing));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Max Bytes (optional)'), '10 GB');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(submitted, isFalse);
      expect(find.text('Enter a whole number, or leave blank for unlimited.'),
          findsOneWidget);
    });
  });

  testWidgets('a blank optional numeric field still means unlimited',
      (tester) async {
    StreamConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.>');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config, isNotNull);
    expect(config!.maxMsgs, -1);
    expect(config!.maxBytes, -1);
    expect(config!.maxAge, isNull);
  });
}
