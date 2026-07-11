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
          onSend: (_, __, ___, ____) {},
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
          onSend: (subject, data, useJetStream, headers) {
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
          onSend: (_, __, useJetStream, ___) => sentUseJetStream = useJetStream,
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
          onSend: (subject, data, _, __) {
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
                  onSend: (_, __, ___, ____) {},
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

  testWidgets('shows "No headers" with no rows and no Add-button prefill',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(),
          dataController: TextEditingController(),
          onSend: (_, __, ___, ____) {},
        ),
      ),
    ));

    expect(find.text('No headers'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Key'), findsNothing);
  });

  testWidgets('Add adds a header row, and sends entered key/value pairs',
      (tester) async {
    Map<String, String>? sentHeaders;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(text: 'orders.new'),
          dataController: TextEditingController(text: '{}'),
          onSend: (_, __, ___, headers) => sentHeaders = headers,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(4)); // subject, data, key, value

    // Field order is subject(0), data(1), header key(2), header value(3).
    await tester.enterText(find.byType(TextFormField).at(2), 'X-Trace-Id');
    await tester.enterText(find.byType(TextFormField).at(3), 'abc-123');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pump();

    expect(sentHeaders, {'X-Trace-Id': 'abc-123'});
  });

  testWidgets('a header row with a blank key is dropped from onSend',
      (tester) async {
    Map<String, String>? sentHeaders;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(text: 'orders.new'),
          dataController: TextEditingController(text: '{}'),
          onSend: (_, __, ___, headers) => sentHeaders = headers,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pump();

    expect(sentHeaders, isEmpty);
  });

  testWidgets('the close icon on a header row removes it', (tester) async {
    Map<String, String>? sentHeaders;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(text: 'orders.new'),
          dataController: TextEditingController(text: '{}'),
          onSend: (_, __, ___, headers) => sentHeaders = headers,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();
    expect(find.text('No headers'), findsNothing);

    await tester.tap(find.byTooltip('Remove header'));
    await tester.pump();
    expect(find.text('No headers'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pump();
    expect(sentHeaders, isEmpty);
  });

  testWidgets('prefills header rows from initialHeaders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendMessageDialog(
          subjectController: TextEditingController(),
          dataController: TextEditingController(),
          initialHeaders: const {'Content-Type': 'application/json'},
          onSend: (_, __, ___, ____) {},
        ),
      ),
    ));

    expect(find.text('No headers'), findsNothing);
    // Field order is subject(0), data(1), header key(2), header value(3).
    expect(
        tester.widget<TextFormField>(find.byType(TextFormField).at(2)).controller?.text,
        'Content-Type');
    expect(
        tester.widget<TextFormField>(find.byType(TextFormField).at(3)).controller?.text,
        'application/json');
  });
}
