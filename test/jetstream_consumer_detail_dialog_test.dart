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
  bool paused = false,
  DateTime? pauseUntil,
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
    paused: paused,
    pauseUntil: pauseUntil,
  );
}

ConsumerDetail _consumerDetail(
  ConsumerInfo info, {
  Duration? ackWait,
  int? maxDeliver,
  int? maxAckPending,
  DateTime? pauseUntil,
}) {
  return ConsumerDetail(
    info: info,
    pauseUntil: pauseUntil ?? info.pauseUntil,
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
        onRefresh: () async =>
            _consumerDetail(_consumerInfo(numPending: numPending++)),
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
        onPause: (_) async {},
      ),
    );

    expect(refreshCalls, 0);
    expect(find.text('(ephemeral consumer)'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Tail'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Pause'))
          .onPressed,
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
        onRefresh: () async => throw NatsException('consumer not found'),
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

  testWidgets(
      'a non-paused consumer shows a Pause button; confirming a duration '
      'calls onPause then refreshes without closing the dialog',
      (tester) async {
    final info = _consumerInfo();
    Duration? pausedFor;
    var refreshCalls = 0;
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async {
          refreshCalls++;
          // The second refresh (after Pause) reflects the now-paused state.
          if (refreshCalls > 1) {
            return _consumerDetail(_consumerInfo(
                paused: true,
                pauseUntil: DateTime.utc(2026, 1, 1, 0, 5, 0)));
          }
          return _consumerDetail(info);
        },
        onPause: (duration) async => pausedFor = duration,
      ),
    );

    expect(find.widgetWithText(TextButton, 'Resume'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Pause'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Pause for how many minutes'),
        '5');
    await tester.tap(find.widgetWithText(TextButton, 'Pause').last);
    await tester.pumpAndSettle();

    expect(pausedFor, const Duration(minutes: 5));
    expect(find.byType(ConsumerDetailDialog), findsOneWidget);
    expect(find.textContaining('Paused until:'), findsOneWidget);
  });

  testWidgets('cancelling the pause-duration prompt calls neither callback',
      (tester) async {
    final info = _consumerInfo();
    var paused = false;
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async => _consumerDetail(info),
        onPause: (_) async => paused = true,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(paused, isFalse);
    expect(find.byType(ConsumerDetailDialog), findsOneWidget);
  });

  testWidgets('a paused consumer shows Resume instead of Pause; tapping it '
      'calls onResume then refreshes', (tester) async {
    final info =
        _consumerInfo(paused: true, pauseUntil: DateTime.utc(2026, 1, 1));
    var resumeCalls = 0;
    var refreshCalls = 0;
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async {
          refreshCalls++;
          if (refreshCalls > 1) return _consumerDetail(_consumerInfo());
          return _consumerDetail(info);
        },
        onResume: () async => resumeCalls++,
      ),
    );

    expect(find.text('Pause'), findsNothing);
    expect(find.textContaining('Paused until:'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(resumeCalls, 1);
    expect(find.textContaining('Paused until:'), findsNothing);
  });

  testWidgets('shows an error message when resume fails, without closing',
      (tester) async {
    final info =
        _consumerInfo(paused: true, pauseUntil: DateTime.utc(2026, 1, 1));
    await _pump(
      tester,
      ConsumerDetailDialog(
        initial: info,
        onRefresh: () async => _consumerDetail(info),
        onResume: () async => throw NatsException('resume failed'),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(find.textContaining('resume failed'), findsOneWidget);
    expect(find.byType(ConsumerDetailDialog), findsOneWidget);
  });
}
