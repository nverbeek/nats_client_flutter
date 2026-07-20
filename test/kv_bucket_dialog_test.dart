import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/kv_bucket_dialog.dart';
import 'package:nats_client_flutter/kv_manager.dart';

void main() {
  Widget buildDialog(void Function(String, int, Duration?, int) onCreate) {
    return MaterialApp(
      home: Scaffold(body: CreateBucketDialog(onCreate: onCreate)),
    );
  }

  testWidgets('shows a validation error and blocks submit for an empty name',
      (tester) async {
    var created = false;
    await tester.pumpWidget(buildDialog((_, __, ___, ____) => created = true));

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(created, isFalse);
    expect(find.text('A bucket name is required.'), findsOneWidget);
  });

  testWidgets(
      'shows a validation error and blocks submit for an invalid history depth',
      (tester) async {
    var created = false;
    await tester.pumpWidget(buildDialog((_, __, ___, ____) => created = true));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'app-config');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'History Depth'), '0');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(created, isFalse);
    expect(find.text('Enter a whole number of at least 1.'), findsOneWidget);
  });

  testWidgets('Create calls onCreate with default history and no TTL',
      (tester) async {
    String? bucket;
    int? history;
    Duration? ttl;
    int? replicas;
    await tester.pumpWidget(buildDialog((b, h, t, r) {
      bucket = b;
      history = h;
      ttl = t;
      replicas = r;
    }));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'app-config');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(bucket, 'app-config');
    expect(history, 1);
    expect(ttl, isNull);
    expect(replicas, 1);
  });

  testWidgets('a TTL value is converted to a Duration in days', (tester) async {
    Duration? ttl;
    await tester.pumpWidget(buildDialog((_, __, t, ____) => ttl = t));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'app-config');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'TTL (days, optional)'), '30');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(ttl, const Duration(days: 30));
  });

  testWidgets('selecting a Replicas value passes it through', (tester) async {
    int? replicas;
    await tester.pumpWidget(buildDialog((_, __, ___, r) => replicas = r));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'app-config');

    // The History Depth field also shows "1" (its default value), so scope
    // the tap to the Replicas dropdown specifically rather than the
    // ambiguous top-level `find.text('1')`.
    await tester.tap(find.descendant(
        of: find.byType(DropdownButtonFormField<int>),
        matching: find.text('1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(replicas, 5);
  });

  testWidgets('Cancel does not call onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => CreateBucketDialog(
                    onCreate: (_, __, ___, ____) => created = true),
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
    expect(find.byType(CreateBucketDialog), findsNothing);
  });

  group('KvBucketStatusDialog', () {
    Future<void> pumpStatusDialog(WidgetTester tester,
        Future<KvBucketStatus> Function() onRefresh) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => KvBucketStatusDialog(
                      bucket: 'app-config', onRefresh: onRefresh),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
    }

    testWidgets('fetches and renders the status snapshot on open',
        (tester) async {
      var refreshCalls = 0;
      await pumpStatusDialog(tester, () async {
        refreshCalls++;
        return KvBucketStatus(
          bucket: 'app-config',
          history: 5,
          storage: 'file',
          size: 2048,
          values: 12,
          ttl: const Duration(days: 30),
          replicas: 3,
        );
      });
      await tester.pumpAndSettle();

      expect(refreshCalls, 1);
      expect(find.text('Bucket Info: app-config'), findsOneWidget);
      expect(find.text('Storage: file'), findsOneWidget);
      expect(find.text('History Depth: 5'), findsOneWidget);
      expect(find.text('TTL: 30 days'), findsOneWidget);
      expect(find.text('Replicas: 3'), findsOneWidget);
      expect(find.text('Values: 12'), findsOneWidget);
      expect(find.text('Size: 2.0 KB'), findsOneWidget);
    });

    testWidgets('shows "unlimited" for a bucket with no TTL', (tester) async {
      await pumpStatusDialog(
        tester,
        () async => KvBucketStatus(
          bucket: 'app-config',
          history: 1,
          storage: 'file',
          size: 0,
          values: 0,
          ttl: null,
          replicas: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TTL: unlimited'), findsOneWidget);
    });

    testWidgets('Refresh button re-fetches and replaces the displayed data',
        (tester) async {
      var replicas = 1;
      await pumpStatusDialog(
        tester,
        () async => KvBucketStatus(
          bucket: 'app-config',
          history: 1,
          storage: 'file',
          size: 0,
          values: 0,
          ttl: null,
          replicas: replicas++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Replicas: 1'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('Replicas: 2'), findsOneWidget);
      expect(find.text('Replicas: 1'), findsNothing);
    });

    testWidgets('shows an error message when the fetch fails', (tester) async {
      await pumpStatusDialog(
        tester,
        () async => throw NatsException('jetstream not enabled for account'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This server or account does not have JetStream enabled.'),
        findsOneWidget,
      );
    });

    testWidgets('Close button dismisses the dialog', (tester) async {
      await pumpStatusDialog(
        tester,
        () async => KvBucketStatus(
          bucket: 'app-config',
          history: 1,
          storage: 'file',
          size: 0,
          values: 0,
          ttl: null,
          replicas: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Bucket Info: app-config'), findsNothing);
    });
  });
}
