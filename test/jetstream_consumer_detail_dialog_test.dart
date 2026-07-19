import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_consumer_detail_dialog.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';

ConsumerInfo _consumerInfo({
  String name = 'my-consumer',
  String streamName = 'orders',
  String created = '',
  String? deliverSubject,
  String? filterSubject,
  String ackPolicy = 'explicit',
  String deliverPolicy = 'all',
  int numPending = 0,
  int numWaiting = 0,
  int numAckPending = 0,
  int numRedelivered = 0,
}) {
  return ConsumerInfo(
    type: '',
    streamName: streamName,
    name: name,
    created: created,
    config: ConsumerConfig(
      durable: name.isEmpty ? null : name,
      deliverSubject: deliverSubject,
      filterSubject: filterSubject,
      ackPolicy: ackPolicy,
      deliverPolicy: deliverPolicy,
    ),
    numPending: numPending,
    numWaiting: numWaiting,
    numAckPending: numAckPending,
    numRedelivered: numRedelivered,
  );
}

ConsumerDetail _consumerDetail(
  ConsumerInfo info, {
  Duration? ackWait,
  int? maxDeliver,
  int? maxAckPending,
}) {
  return ConsumerDetail(
    info: info,
    ackWait: ackWait,
    maxDeliver: maxDeliver,
    maxAckPending: maxAckPending,
  );
}

Future<void> _pump(WidgetTester tester, ConsumerDetailDialog dialog) async {
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
  testWidgets(
      'fetches consumer detail on open and renders ack-wait/max-deliver/max-ack-pending',
      (tester) async {
    var refreshCalls = 0;
    final info = _consumerInfo(created: '2026-07-19T00:00:00Z', numPending: 4);
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async {
          refreshCalls++;
          return _consumerDetail(info,
              ackWait: const Duration(seconds: 45),
              maxDeliver: 5,
              maxAckPending: 200);
        },
      ),
    );

    expect(refreshCalls, 1);
    expect(find.text('my-consumer'), findsOneWidget);
    expect(find.text('Type: Pull'), findsOneWidget);
    expect(find.text('Created: 2026-07-19T00:00:00Z'), findsOneWidget);
    expect(find.text('Ack Wait: 45s'), findsOneWidget);
    expect(find.text('Max Deliver: 5'), findsOneWidget);
    expect(find.text('Max Ack Pending: 200'), findsOneWidget);
    expect(find.text('Pending: 4'), findsOneWidget);
  });

  testWidgets('shows "unlimited" for a -1 max-deliver/max-ack-pending sentinel',
      (tester) async {
    final info = _consumerInfo();
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async =>
            _consumerDetail(info, maxDeliver: -1, maxAckPending: -1),
      ),
    );

    expect(find.text('Max Deliver: unlimited'), findsOneWidget);
    expect(find.text('Max Ack Pending: unlimited'), findsOneWidget);
  });

  testWidgets('Refresh button re-fetches and replaces the displayed counters',
      (tester) async {
    var numPending = 1;
    final info = _consumerInfo();
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async => _consumerDetail(
            _consumerInfo(numPending: numPending++)),
      ),
    );

    expect(find.text('Pending: 1'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('Pending: 2'), findsOneWidget);
    expect(find.text('Pending: 1'), findsNothing);
  });

  testWidgets(
      'an ephemeral (nameless) consumer skips the refresh fetch and disables Refresh/Delete/Tail',
      (tester) async {
    var refreshCalls = 0;
    final info = _consumerInfo(name: '');
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async {
          refreshCalls++;
          return _consumerDetail(info);
        },
        onDelete: () {},
        onTail: () {},
      ),
    );

    expect(refreshCalls, 0);
    expect(find.text('(ephemeral consumer)'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Tail')).onPressed,
      isNull,
    );
  });

  testWidgets('Delete button pops the dialog and invokes onDelete',
      (tester) async {
    var deleted = false;
    final info = _consumerInfo();
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async => _consumerDetail(info),
        onDelete: () => deleted = true,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.byType(ConsumerDetailDialog), findsNothing);
  });

  testWidgets('Tail button pops the dialog and invokes onTail', (tester) async {
    var tailed = false;
    final info = _consumerInfo();
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async => _consumerDetail(info),
        onTail: () => tailed = true,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Tail'));
    await tester.pumpAndSettle();

    expect(tailed, isTrue);
    expect(find.byType(ConsumerDetailDialog), findsNothing);
  });

  testWidgets('shows an error message when the refresh fetch fails',
      (tester) async {
    final info = _consumerInfo();
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async =>
            throw NatsException('consumer not found'),
      ),
    );

    expect(find.textContaining('consumer not found'), findsOneWidget);
    // The static snapshot from `initial` still renders underneath the error.
    expect(find.text('my-consumer'), findsOneWidget);
  });

  testWidgets('Close button dismisses the dialog', (tester) async {
    final info = _consumerInfo();
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async => _consumerDetail(info),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.byType(ConsumerDetailDialog), findsNothing);
  });
}
