import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_dashboard.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';

/// Test double for [JetStreamManager]. `Client` itself can't be faked (it's
/// a concrete class backed by real socket/stream logic), but none of
/// [JetStreamManager]'s methods are `final`, so overriding them here lets
/// widget tests drive the dashboard's connected states without a live
/// server. `browseStream()` is deliberately not overridable in a useful way
/// (it returns a concrete `OrderedConsumer` bound to a real `Client`), so
/// the "Browse Messages" tail view remains covered only by manual testing —
/// see AGENTS.md "Recipe E: Local JetStream Testing".
class FakeJetStreamManager extends JetStreamManager {
  FakeJetStreamManager() : super(Client());

  Future<String?> Function() checkAvailabilityImpl = () async => null;
  Future<List<StreamInfo>> Function() listStreamsImpl = () async => [];
  Future<List<ConsumerInfo>> Function(String) listConsumersImpl =
      (_) async => [];

  int checkAvailabilityCalls = 0;
  int listStreamsCalls = 0;

  @override
  Future<String?> checkAvailability({Duration? timeout}) {
    checkAvailabilityCalls++;
    return checkAvailabilityImpl();
  }

  @override
  Future<List<StreamInfo>> listStreams({Duration? timeout}) {
    listStreamsCalls++;
    return listStreamsImpl();
  }

  @override
  Future<List<ConsumerInfo>> listConsumers(String streamName,
      {Duration? timeout}) {
    return listConsumersImpl(streamName);
  }
}

StreamInfo _stream(String name, {int messages = 0, int bytes = 0}) {
  return StreamInfo(
    type: 'io.nats.jetstream.api.v1.stream_info_response',
    config: StreamConfig(name: name, subjects: ['$name.>']),
    created: DateTime.now().toIso8601String(),
    state: StreamState(
      messages: messages,
      bytes: bytes,
      firstSeq: 1,
      firstTs: DateTime.now().toIso8601String(),
      lastSeq: messages,
      lastTs: DateTime.now().toIso8601String(),
      consumerCount: 0,
    ),
  );
}

ConsumerInfo _consumer(String name, {String ackPolicy = 'explicit'}) {
  return ConsumerInfo(
    type: 'io.nats.jetstream.api.v1.consumer_info_response',
    streamName: 'orders',
    name: name,
    created: DateTime.now().toIso8601String(),
    config: ConsumerConfig(durable: name, ackPolicy: ackPolicy),
    numPending: 0,
    numWaiting: 0,
    numAckPending: 0,
    numRedelivered: 0,
  );
}

void main() {
  testWidgets('shows a connect prompt when there is no active manager',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: JetStreamDashboard(manager: null)),
      ),
    );

    expect(find.text('Connect to a NATS server to use JetStream.'),
        findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('shows a loading state while checking availability',
      (tester) async {
    final availability = Completer<String?>();
    final manager = FakeJetStreamManager();
    manager.checkAvailabilityImpl = () => availability.future;

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pump();

    expect(find.text('Checking JetStream availability...'), findsOneWidget);

    availability.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('shows a friendly error with retry when JetStream is unavailable',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.checkAvailabilityImpl =
        () async => 'This server or account does not have JetStream enabled.';

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This server or account does not have JetStream enabled.'),
      findsOneWidget,
    );
    expect(manager.checkAvailabilityCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(manager.checkAvailabilityCalls, 2);
  });

  testWidgets('lists streams once JetStream is available', (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [
          _stream('orders', messages: 42, bytes: 2048),
          _stream('telemetry', messages: 7),
        ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(find.text('orders'), findsOneWidget);
    expect(find.text('telemetry'), findsOneWidget);
    expect(find.textContaining('42 msgs'), findsOneWidget);
    expect(find.text('Select a stream to see details.'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no streams', (tester) async {
    final manager = FakeJetStreamManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(find.text('No streams found on this account.'), findsOneWidget);
  });

  testWidgets('selecting a stream loads and displays its consumers',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 5)];
    manager.listConsumersImpl =
        (streamName) async => [_consumer('billing-processor')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    expect(find.text('billing-processor'), findsOneWidget);
    expect(find.textContaining('Ack: explicit'), findsOneWidget);
  });
}
