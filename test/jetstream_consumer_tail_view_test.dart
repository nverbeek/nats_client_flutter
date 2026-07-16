import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:dart_nats/dart_nats.dart' as nats show Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_consumer_tail_view.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';

/// A [nats.Consumer] whose `messages()` never emits or errors on its own --
/// this view's own health probe (backed by [FakeJetStreamManager.consumerInfo]
/// below) is what's under test here, not message delivery, and the real
/// `Consumer.messages()` pull loop needs a live server.
class _FakeConsumer extends nats.Consumer<dynamic> {
  _FakeConsumer(super.js, super.streamName, super.name);

  @override
  Stream<Message<dynamic>> messages(
          {int batch = 1, Duration timeout = const Duration(seconds: 5)}) =>
      const Stream.empty();
}

class FakeJetStreamManager extends JetStreamManager {
  FakeJetStreamManager() : super(Client());

  Future<ConsumerInfo> Function(String, String)? consumerInfoImpl;
  int consumerInfoCalls = 0;

  @override
  nats.Consumer<dynamic> tailConsumer(String streamName, String consumerName) {
    return _FakeConsumer(client.jetStream(), streamName, consumerName);
  }

  @override
  Future<ConsumerInfo> consumerInfo(String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 5)}) {
    consumerInfoCalls++;
    if (consumerInfoImpl != null) {
      return consumerInfoImpl!(streamName, consumerName);
    }
    return Future.value(_fakeConsumerInfo(streamName, consumerName));
  }
}

ConsumerInfo _fakeConsumerInfo(String streamName, String name) => ConsumerInfo(
      type: 'io.nats.jetstream.api.v1.consumer_info_response',
      streamName: streamName,
      name: name,
      created: DateTime.now().toIso8601String(),
      config: ConsumerConfig(durable: name, ackPolicy: 'explicit'),
      numPending: 0,
      numWaiting: 0,
      numAckPending: 0,
      numRedelivered: 0,
    );

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
      'a consumer that stops existing server-side flips the dot to grey and '
      'surfaces a Retry row within one probe interval',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.consumerInfoImpl =
        (_, __) async => throw Exception('consumer not found');

    await tester.pumpWidget(buildView(manager));
    await tester.pump();
    // Before the first probe fires, the view still looks healthy.
    expect(find.byIcon(Icons.error_outline), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('JetStream is unavailable'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    final dot = tester.widget<Icon>(find.byIcon(Icons.circle));
    expect(dot.color, Colors.grey.shade500);
  });

  testWidgets('Retry clears the error and probes again', (tester) async {
    final manager = FakeJetStreamManager();
    var shouldFail = true;
    manager.consumerInfoImpl = (_, __) async {
      if (shouldFail) throw Exception('consumer not found');
      return _fakeConsumerInfo('ORDERS', 'worker-1');
    };

    await tester.pumpWidget(buildView(manager));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Waiting for messages...'), findsOneWidget);
  });

  testWidgets('overlapping probes are guarded -- a slow probe is not '
      'restarted before it resolves', (tester) async {
    final manager = FakeJetStreamManager();
    final probeStarted = Completer<void>();
    final probeFinish = Completer<ConsumerInfo>();
    manager.consumerInfoImpl = (streamName, name) {
      if (!probeStarted.isCompleted) probeStarted.complete();
      return probeFinish.future;
    };

    await tester.pumpWidget(buildView(manager));
    await tester.pump(const Duration(seconds: 5));
    await probeStarted.future;
    expect(manager.consumerInfoCalls, 1);

    // A second interval elapses while the first probe is still in flight --
    // `_probeInFlight` should prevent a second overlapping call.
    await tester.pump(const Duration(seconds: 5));
    expect(manager.consumerInfoCalls, 1);

    probeFinish.complete(_fakeConsumerInfo('ORDERS', 'worker-1'));
    await tester.pump();
  });
}
