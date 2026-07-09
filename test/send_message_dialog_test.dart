import 'package:flutter/material.dart';
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
}
