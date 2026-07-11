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
  Future<void> Function(StreamConfig)? createStreamImpl;
  Future<void> Function(String)? deleteStreamImpl;
  Future<void> Function(String)? purgeStreamImpl;
  Future<void> Function(String, ConsumerConfig)? createConsumerImpl;
  Future<void> Function(String, String)? deleteConsumerImpl;

  Future<AccountInfo> Function()? fetchAccountInfoImpl;

  int checkAvailabilityCalls = 0;
  int listStreamsCalls = 0;
  int deleteStreamCalls = 0;
  int purgeStreamCalls = 0;
  int deleteConsumerCalls = 0;
  int fetchAccountInfoCalls = 0;
  StreamConfig? lastCreatedStreamConfig;
  ConsumerConfig? lastCreatedConsumerConfig;

  @override
  Future<String?> checkAvailability({Duration? timeout}) {
    checkAvailabilityCalls++;
    return checkAvailabilityImpl();
  }

  @override
  Future<AccountInfo> fetchAccountInfo({Duration? timeout}) {
    fetchAccountInfoCalls++;
    return fetchAccountInfoImpl!();
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

  @override
  Future<void> createStream(StreamConfig config, {Duration? timeout}) async {
    lastCreatedStreamConfig = config;
    if (createStreamImpl != null) return createStreamImpl!(config);
  }

  @override
  Future<void> deleteStream(String streamName, {Duration? timeout}) async {
    deleteStreamCalls++;
    if (deleteStreamImpl != null) return deleteStreamImpl!(streamName);
  }

  @override
  Future<void> purgeStream(String streamName, {Duration? timeout}) async {
    purgeStreamCalls++;
    if (purgeStreamImpl != null) return purgeStreamImpl!(streamName);
  }

  @override
  Future<void> createConsumer(String streamName, ConsumerConfig config,
      {Duration? timeout}) async {
    lastCreatedConsumerConfig = config;
    if (createConsumerImpl != null) {
      return createConsumerImpl!(streamName, config);
    }
  }

  @override
  Future<void> deleteConsumer(String streamName, String consumerName,
      {Duration? timeout}) async {
    deleteConsumerCalls++;
    if (deleteConsumerImpl != null) {
      return deleteConsumerImpl!(streamName, consumerName);
    }
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

  testWidgets('Add Stream dialog creates a stream via the manager',
      (tester) async {
    final manager = FakeJetStreamManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Stream'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), 'orders');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        'orders.>');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(manager.lastCreatedStreamConfig?.name, 'orders');
    expect(manager.lastCreatedStreamConfig?.subjects, ['orders.>']);
    expect(find.text('Stream "orders" created.'), findsOneWidget);
  });

  testWidgets('Purge and Delete Stream buttons confirm then call the manager',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 5)];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
    await tester.pumpAndSettle();
    expect(find.text('Purge Stream?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();
    expect(manager.purgeStreamCalls, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Stream'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Stream?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(manager.deleteStreamCalls, 1);
    expect(find.text('Select a stream to see details.'), findsOneWidget);
  });

  testWidgets(
      'a mutation failure shows an error SnackBar with contrast-safe (onError) text',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 5)];
    manager.purgeStreamImpl = (_) async => throw Exception('purge boom');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final colorScheme = Theme.of(tester.element(find.byType(SnackBar))).colorScheme;
    expect(snackBar.backgroundColor, colorScheme.error);
    final content = snackBar.content as Text;
    expect(content.style?.color, colorScheme.onError);
  });

  testWidgets('Create Consumer dialog creates a consumer via the manager',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 5)];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Consumer'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Durable Name (optional)'),
        'billing-processor');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(manager.lastCreatedConsumerConfig?.durable, 'billing-processor');
    expect(find.text('Consumer created.'), findsOneWidget);
  });

  testWidgets('deleting a consumer confirms then calls the manager',
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

    await tester.tap(find.byTooltip('Delete consumer'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Consumer?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(manager.deleteConsumerCalls, 1);
    expect(find.text('Consumer "billing-processor" deleted.'), findsOneWidget);
  });

  testWidgets('Refresh streams button re-invokes listStreams', (tester) async {
    final manager = FakeJetStreamManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    expect(manager.listStreamsCalls, 1);

    await tester.tap(find.byTooltip('Refresh streams'));
    await tester.pumpAndSettle();

    expect(manager.listStreamsCalls, 2);
  });

  testWidgets('stream-list Retry button re-invokes listStreams after a failure',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => throw Exception('stream list boom');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('JetStream is unavailable'), findsOneWidget);

    manager.listStreamsImpl = () async => [_stream('orders', messages: 3)];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('orders'), findsOneWidget);
  });

  testWidgets(
      'consumer-list Retry button re-invokes listConsumers after a failure',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 3)];
    manager.listConsumersImpl =
        (_) async => throw Exception('consumer list boom');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    expect(find.textContaining('JetStream is unavailable'), findsOneWidget);

    manager.listConsumersImpl =
        (_) async => [_consumer('billing-processor')];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('billing-processor'), findsOneWidget);
  });

  testWidgets('Browse Messages is disabled when the stream has no messages',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 0)];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    final browseButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Browse Messages'));
    expect(browseButton.onPressed, isNull);
  });

  testWidgets('an ephemeral consumer hides its row delete icon and disables '
      'Delete/Tail in its detail dialog', (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 3)];
    manager.listConsumersImpl = (_) async => [_consumer('')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    expect(find.text('(ephemeral)'), findsOneWidget);
    expect(find.byTooltip('Delete consumer'), findsNothing);

    await tester.tap(find.text('(ephemeral)'));
    await tester.pumpAndSettle();

    final deleteButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete'));
    final tailButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Tail'));
    expect(deleteButton.onPressed, isNull);
    expect(tailButton.onPressed, isNull);
  });

  testWidgets(
      'Consumer Detail dialog Delete button confirms then calls the manager',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 3)];
    manager.listConsumersImpl =
        (_) async => [_consumer('billing-processor')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('billing-processor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Consumer?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(manager.deleteConsumerCalls, 1);
    expect(find.text('Consumer "billing-processor" deleted.'), findsOneWidget);
  });

  testWidgets('Consumer Detail dialog Close button dismisses without acting',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.listStreamsImpl = () async => [_stream('orders', messages: 3)];
    manager.listConsumersImpl =
        (_) async => [_consumer('billing-processor')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('billing-processor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(manager.deleteConsumerCalls, 0);
    expect(find.text('billing-processor'), findsOneWidget);
  });

  testWidgets(
      'Account info button shows the cached snapshot without refetching',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.lastAccountInfo = AccountInfo(
      domain: 'hub',
      api: APIStats(level: 1, total: 10, errors: 1, inflight: 0),
      tier: Tier(
        memory: 1024,
        storage: 2048,
        reservedMemory: 4096,
        reservedStorage: 0,
        streams: 3,
        consumers: 5,
      ),
      tiers: const {},
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Account Info'), findsOneWidget);
    expect(find.text('Domain: hub'), findsOneWidget);
    expect(find.text('3 streams'), findsOneWidget);
    expect(find.text('5 consumers'), findsOneWidget);
    expect(find.textContaining('Memory:'), findsOneWidget);
    expect(find.textContaining('Storage: 2.0 KB'), findsOneWidget);
    expect(manager.fetchAccountInfoCalls, 0);
  });

  testWidgets('Account info dialog fetches fresh data when nothing cached',
      (tester) async {
    final manager = FakeJetStreamManager();
    manager.fetchAccountInfoImpl = () async => AccountInfo(
          domain: '',
          api: APIStats(level: 0, total: 0, errors: 0, inflight: 0),
          tier: Tier(
            memory: 0,
            storage: 0,
            reservedMemory: 0,
            reservedStorage: 0,
            streams: 0,
            consumers: 0,
          ),
          tiers: const {},
        );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JetStreamDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.info_outline));
    await tester.pumpAndSettle();

    expect(manager.fetchAccountInfoCalls, 1);
    expect(find.text('0 streams'), findsOneWidget);
  });
}
