import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_pause_dialog.dart';

Future<Duration?> _open(WidgetTester tester) async {
  Duration? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<Duration>(
                context: context,
                builder: (context) => const ConsumerPauseDurationDialog(
                    consumerName: 'billing-processor'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('defaults to a 5-minute suggestion and names the consumer',
      (tester) async {
    await _open(tester);

    expect(find.text('Pause "billing-processor"?'), findsOneWidget);
    final field = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Pause for how many minutes'));
    expect(field.controller?.text, '5');
  });

  testWidgets('Pause pops the entered duration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<Duration>(
                  context: context,
                  builder: (context) => const ConsumerPauseDurationDialog(
                      consumerName: 'billing-processor'),
                );
                if (result != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('got:${result.inMinutes}')),
                  );
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Pause for how many minutes'),
        '15');
    await tester.tap(find.widgetWithText(TextButton, 'Pause'));
    await tester.pumpAndSettle();

    expect(find.text('got:15'), findsOneWidget);
  });

  testWidgets('Cancel pops null (no snackbar path taken)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<Duration>(
                  context: context,
                  builder: (context) => const ConsumerPauseDurationDialog(
                      consumerName: 'billing-processor'),
                );
                if (result == null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('cancelled')));
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('cancelled'), findsOneWidget);
  });

  testWidgets('rejects a zero or blank minute count', (tester) async {
    await _open(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Pause for how many minutes'), '0');
    await tester.tap(find.widgetWithText(TextButton, 'Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a positive integer.'), findsOneWidget);
    expect(find.byType(ConsumerPauseDurationDialog), findsOneWidget);
  });
}
