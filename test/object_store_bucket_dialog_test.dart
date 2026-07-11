import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/object_store_bucket_dialog.dart';

void main() {
  Widget buildDialog(
      void Function(String, String, int, int, Duration?) onCreate) {
    return MaterialApp(
      home: Scaffold(
          body: CreateObjectStoreBucketDialog(onCreate: onCreate)),
    );
  }

  testWidgets('shows a validation error and blocks submit for an empty name',
      (tester) async {
    var created = false;
    await tester
        .pumpWidget(buildDialog((_, __, ___, ____, _____) => created = true));

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(created, isFalse);
    expect(find.text('A bucket name is required.'), findsOneWidget);
  });

  testWidgets(
      'Create calls onCreate with default storage/replicas and no max size/TTL',
      (tester) async {
    String? bucket;
    String? storage;
    int? replicas;
    int? maxBytes;
    Duration? ttl;
    await tester.pumpWidget(buildDialog((b, s, r, m, t) {
      bucket = b;
      storage = s;
      replicas = r;
      maxBytes = m;
      ttl = t;
    }));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'documents');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(bucket, 'documents');
    expect(storage, 'file');
    expect(replicas, 1);
    expect(maxBytes, -1);
    expect(ttl, isNull);
  });

  testWidgets('a Max Size value is converted to bytes', (tester) async {
    int? maxBytes;
    await tester.pumpWidget(buildDialog((_, __, ___, m, ____) => maxBytes = m));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'documents');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max Size (MB, optional)'), '10');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(maxBytes, 10 * 1024 * 1024);
  });

  testWidgets('a TTL value is converted to a Duration in days', (tester) async {
    Duration? ttl;
    await tester.pumpWidget(buildDialog((_, __, ___, ____, t) => ttl = t));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'documents');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'TTL (days, optional)'), '30');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(ttl, const Duration(days: 30));
  });

  testWidgets('selecting Memory storage passes it through', (tester) async {
    String? storage;
    await tester.pumpWidget(buildDialog((_, s, __, ___, ____) => storage = s));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'documents');

    await tester.tap(find.descendant(
        of: find.byType(DropdownButtonFormField<String>),
        matching: find.text('File')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(storage, 'memory');
  });

  testWidgets('selecting a Replicas value passes it through', (tester) async {
    int? replicas;
    await tester.pumpWidget(buildDialog((_, __, r, ___, ____) => replicas = r));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'documents');

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
                builder: (context) => CreateObjectStoreBucketDialog(
                    onCreate: (_, __, ___, ____, _____) => created = true),
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
    expect(find.byType(CreateObjectStoreBucketDialog), findsNothing);
  });
}
