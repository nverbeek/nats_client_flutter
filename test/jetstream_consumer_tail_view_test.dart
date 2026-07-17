import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:dart_nats/dart_nats.dart' as nats show Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_consumer_tail_view.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';

/// A [nats.Consumer] whose `messages()` never emits or errors on its own,
/// unless fed via [incoming] -- lets a test drive exactly what the tailed
/// consumer's stream would deliver (messages or a delivery error) without a
/// live server.
class _FakeConsumer extends nats.Consumer<dynamic> {
  _FakeConsumer(super.js, super.streamName, super.name, {this.incoming});

  final Stream<Message<dynamic>>? incoming;

  @override
  Stream<Message<dynamic>> messages(
          {int batch = 1, Duration timeout = const Duration(seconds: 5)}) =>
      incoming ?? const Stream.empty();
}

class FakeJetStreamManager extends JetStreamManager {
  FakeJetStreamManager() : super(Client());

  Stream<Message<dynamic>>? incomingMessages;

  @override
  nats.Consumer<dynamic> tailConsumer(String streamName, String consumerName) {
    return _FakeConsumer(client.jetStream(), streamName, consumerName,
        incoming: incomingMessages);
  }
}

void main() {
  Widget buildView(FakeJetStreamManager manager) {
    return MaterialApp(
      home: Scaffold(
        body: JetStreamConsumerTailView(
          streamName: 'ORDERS',
          consumerName: 'worker-1',
          explicitAck: true,
          manager: manager,
          onClose: () {},
        ),
      ),
    );
  }

  testWidgets(
      'a healthy consumer keeps the live (green) dot and shows no error',
      (tester) async {
    final manager = FakeJetStreamManager();

    await tester.pumpWidget(buildView(manager));
    await tester.pump();

    expect(find.text('Waiting for messages...'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    final dot = tester.widget<Icon>(find.byIcon(Icons.circle));
    expect(dot.color, Colors.green.shade400);
  });

  testWidgets(
      'a stream delivery error (e.g. the consumer was deleted server-side) '
      'flips the dot to grey and surfaces a Retry row', (tester) async {
    final incoming = StreamController<Message<dynamic>>();
    final manager = FakeJetStreamManager();
    manager.incomingMessages = incoming.stream;

    await tester.pumpWidget(buildView(manager));
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsNothing);

    // dart_nats 1.2.2's pull-consumer loop surfaces a deleted/unreachable
    // consumer via the stream's own error channel (see jetstream.dart's
    // `Consumer.messages()`) -- this view's `onError` is what's under test,
    // not any app-side polling.
    incoming.addError(Exception('consumer not found'));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('consumer not found'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    final dot = tester.widget<Icon>(find.byIcon(Icons.circle));
    expect(dot.color, Colors.grey.shade500);
  });

  testWidgets('Retry clears the error and re-subscribes', (tester) async {
    // Broadcast (not single-subscription) because Retry re-subscribes to the
    // same fake stream -- a single-subscription controller can only ever be
    // listened to once, even after its first subscription is cancelled.
    final incoming = StreamController<Message<dynamic>>.broadcast();
    final manager = FakeJetStreamManager();
    manager.incomingMessages = incoming.stream;

    await tester.pumpWidget(buildView(manager));
    incoming.addError(Exception('consumer not found'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Waiting for messages...'), findsOneWidget);
  });

  testWidgets(
      'a failed ack reverts the optimistic resolution and shows a snackbar',
      (tester) async {
    final incoming = StreamController<Message<dynamic>>();
    final manager = FakeJetStreamManager();
    manager.incomingMessages = incoming.stream;

    await tester.pumpWidget(buildView(manager));
    await tester.pump();

    // A fresh, never-connected Client -- ackSync()'s underlying
    // Client.request() throws synchronously since `connected` is false,
    // simulating the ack publish never reaching the server.
    final message = Message<dynamic>(
      'ORDERS.new',
      1,
      Uint8List.fromList(utf8.encode('payload')),
      Client(),
      replyTo: r'$JS.ACK.ORDERS.worker-1.1.1.1.0.0',
    );
    incoming.add(message);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Ack'));
    await tester.pump();

    expect(find.textContaining('Ack failed'), findsOneWidget);
    final ackButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.check_circle_outline));
    expect(ackButton.onPressed, isNotNull,
        reason: 'the button should re-enable after the revert');

    await incoming.close();
  });

  testWidgets('the row menu copies the subject via Copy Subject',
      (tester) async {
    final incoming = StreamController<Message<dynamic>>();
    final manager = FakeJetStreamManager();
    manager.incomingMessages = incoming.stream;

    await tester.pumpWidget(buildView(manager));
    await tester.pump();

    final message = Message<dynamic>(
      'ORDERS.new',
      1,
      Uint8List.fromList(utf8.encode('payload')),
      Client(),
    );
    incoming.add(message);
    await tester.pump();
    await tester.pump();

    final copiedData = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Subject'));
    await tester.pumpAndSettle();

    expect(copiedData, contains('ORDERS.new'));

    await incoming.close();
  });
}
