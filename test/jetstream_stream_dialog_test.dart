import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_stream_dialog.dart';

void main() {
  Widget buildDialog(void Function(StreamConfig) onCreate) {
    return MaterialApp(
      home: Scaffold(body: CreateStreamDialog(onCreate: onCreate)),
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

  testWidgets(
      'shows a validation error and blocks submit for empty subjects',
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

  testWidgets('Create calls onCreate with the expected StreamConfig',
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

  testWidgets('selecting a Replicas value passes it through',
      (tester) async {
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

  testWidgets('Cancel does not call onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) =>
                    CreateStreamDialog(onCreate: (_) => created = true),
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
    expect(find.byType(CreateStreamDialog), findsNothing);
  });
}
