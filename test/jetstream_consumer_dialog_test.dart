import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_consumer_dialog.dart';

void main() {
  Widget buildDialog(void Function(ConsumerConfig) onCreate) {
    return MaterialApp(
      home: Scaffold(body: CreateConsumerDialog(onCreate: onCreate)),
    );
  }

  testWidgets('defaults to a pull, explicit-ack, all-deliver consumer',
      (tester) async {
    ConsumerConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config, isNotNull);
    expect(config!.durable, isNull);
    expect(config!.deliverSubject, isNull);
    expect(config!.ackPolicy, 'explicit');
    expect(config!.deliverPolicy, 'all');
  });

  testWidgets('durable name and filter subject are passed through',
      (tester) async {
    ConsumerConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Durable Name (optional)'),
        'billing-processor');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Filter Subject (optional)'),
        'orders.created');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config!.durable, 'billing-processor');
    expect(config!.filterSubject, 'orders.created');
  });

  testWidgets(
      'enabling Push Consumer reveals the Deliver Subject field and requires it',
      (tester) async {
    var created = false;
    await tester.pumpWidget(buildDialog((_) => created = true));

    expect(find.widgetWithText(TextFormField, 'Deliver Subject'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(TextFormField, 'Deliver Subject'), findsOneWidget);

    // Leaving it blank should block submit with a validation error.
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();
    expect(created, isFalse);
    expect(find.text('A deliver subject is required for push consumers.'),
        findsOneWidget);
  });

  testWidgets(
      'a filled-in Deliver Subject is passed through for push consumers',
      (tester) async {
    ConsumerConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Deliver Subject'), 'inbox.orders');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config!.deliverSubject, 'inbox.orders');
  });

  testWidgets('Ack Policy and Deliver Policy dropdowns can be changed',
      (tester) async {
    ConsumerConfig? config;
    await tester.pumpWidget(buildDialog((c) => config = c));

    await tester.tap(find.text('Explicit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();

    expect(config!.ackPolicy, 'none');
    expect(config!.deliverPolicy, 'new');
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
                    CreateConsumerDialog(onCreate: (_) => created = true),
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
    expect(find.byType(CreateConsumerDialog), findsNothing);
  });
}
