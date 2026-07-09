import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/send_message_dialog.dart';

void main() {
  testWidgets('hides the JetStream option when unavailable', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(),
          dataController: TextEditingController(),
          onSend: (_, __, ___) {},
        ),
      ),
    ));

    expect(find.text('Publish via JetStream (get delivery ack)'), findsNothing);
  });

  testWidgets('passes useJetStream=true to onSend when the checkbox is checked',
      (tester) async {
    String? sentSubject;
    String? sentData;
    bool? sentUseJetStream;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(text: 'orders.new'),
          dataController: TextEditingController(text: '{}'),
          jetStreamAvailable: true,
          onSend: (subject, data, useJetStream) {
            sentSubject = subject;
            sentData = data;
            sentUseJetStream = useJetStream;
          },
        ),
      ),
    ));

    expect(
        find.text('Publish via JetStream (get delivery ack)'), findsOneWidget);

    await tester.tap(find.text('Publish via JetStream (get delivery ack)'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pump();

    expect(sentSubject, 'orders.new');
    expect(sentData, '{}');
    expect(sentUseJetStream, true);
  });

  testWidgets('defaults useJetStream to false when the checkbox is untouched',
      (tester) async {
    bool? sentUseJetStream;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(text: 'orders.new'),
          dataController: TextEditingController(text: '{}'),
          jetStreamAvailable: true,
          onSend: (_, __, useJetStream) => sentUseJetStream = useJetStream,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pump();

    expect(sentUseJetStream, false);
  });

  testWidgets('Ctrl+Enter sends the message', (tester) async {
    String? sentSubject;
    String? sentData;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(text: 'orders.new'),
          dataController: TextEditingController(text: '{}'),
          onSend: (subject, data, _) {
            sentSubject = subject;
            sentData = data;
          },
        ),
      ),
    ));

    // `find.widgetWithText(TextFormField, 'Subject')` is ambiguous here:
    // both the label and hint use the same "Subject" text and both remain
    // in the tree. The Subject field is the first of the two, so target it
    // positionally instead.
    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(sentSubject, 'orders.new');
    expect(sentData, '{}');
  });

  testWidgets('close icon and Close button both pop the dialog',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => SendMessageDialog(
                  subjectController: TextEditingController(),
                  dataController: TextEditingController(),
                  onSend: (_, __, ___) {},
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SendMessageDialog), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SendMessageDialog), findsNothing);
  });
}
