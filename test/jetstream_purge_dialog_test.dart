import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_purge_dialog.dart';

Future<void> _pump(WidgetTester tester, PurgeStreamDialog dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => dialog,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('defaults to the All scope with no filter, keep, or seq',
      (tester) async {
    String? capturedFilter;
    int? capturedKeep;
    int? capturedSeq;
    var called = false;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) {
          called = true;
          capturedFilter = filter;
          capturedKeep = keep;
          capturedSeq = seq;
        },
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(capturedFilter, isNull);
    expect(capturedKeep, isNull);
    expect(capturedSeq, isNull);
    expect(find.byType(PurgeStreamDialog), findsNothing);
  });

  testWidgets('Cancel dismisses without calling onSubmit', (tester) async {
    var called = false;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) => called = true,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.byType(PurgeStreamDialog), findsNothing);
  });

  testWidgets('trims and passes a non-empty subject filter in the All scope',
      (tester) async {
    String? capturedFilter;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) => capturedFilter = filter,
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject Filter (optional)'),
        '  orders.cancelled  ');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(capturedFilter, 'orders.cancelled');
  });

  testWidgets('rejects an invalid subject filter', (tester) async {
    var called = false;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) => called = true,
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject Filter (optional)'),
        'ord ers');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Not a valid NATS subject.'), findsOneWidget);
  });

  testWidgets('Keep Newest scope validates and passes an int keep count',
      (tester) async {
    int? capturedKeep;
    String? capturedFilter;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) {
          capturedKeep = keep;
          capturedFilter = filter;
        },
      ),
    );

    await tester.tap(find.text('Keep Newest'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Keep newest N messages'), '10');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(capturedKeep, 10);
    expect(capturedFilter, isNull);
  });

  testWidgets('Keep Newest scope rejects a zero or blank count',
      (tester) async {
    var called = false;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) => called = true,
      ),
    );

    await tester.tap(find.text('Keep Newest'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Keep newest N messages'), '0');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Enter a positive integer.'), findsOneWidget);
  });

  testWidgets('Up to Sequence scope validates and passes an int seq',
      (tester) async {
    int? capturedSeq;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) => capturedSeq = seq,
      ),
    );

    await tester.tap(find.text('Up to Seq'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Purge up to sequence'), '42');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(capturedSeq, 42);
  });

  testWidgets(
      'switching scopes hides the previous scope\'s field so its stale '
      'value is never submitted', (tester) async {
    int? capturedKeep;
    int? capturedSeq;
    await _pump(
      tester,
      PurgeStreamDialog(
        streamName: 'orders',
        onSubmit: ({filter, keep, seq}) {
          capturedKeep = keep;
          capturedSeq = seq;
        },
      ),
    );

    await tester.tap(find.text('Keep Newest'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Keep newest N messages'), '10');

    await tester.tap(find.text('Up to Seq'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Keep newest N messages'),
        findsNothing);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Purge up to sequence'), '99');
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(capturedSeq, 99);
    expect(capturedKeep, isNull);
  });
}
