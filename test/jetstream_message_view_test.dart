import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/jetstream_manager.dart';
import 'package:nats_client_flutter/exact_extent_list.dart';
import 'package:nats_client_flutter/jetstream_message_view.dart';
import 'package:nats_client_flutter/live_message_row.dart';
import 'package:nats_client_flutter/message_list_layout.dart';
import 'package:nats_client_flutter/message_row_metrics.dart';

/// An [OrderedConsumer] whose `messages()` is driven entirely by the test
/// via [incoming] and whose `stop()` touches no client/server state — lets a
/// test feed the Browse Messages view without a live NATS server.
class _FakeOrderedConsumer extends OrderedConsumer {
  _FakeOrderedConsumer(super.js, super.stream, super.config, this.incoming);

  final Stream<Message<dynamic>> incoming;

  @override
  Stream<Message<dynamic>> messages() => incoming;

  @override
  void stop() {}
}

class FakeJetStreamManager extends JetStreamManager {
  FakeJetStreamManager() : super(Client());

  final incoming = StreamController<Message<dynamic>>.broadcast();

  @override
  OrderedConsumer browseStream(String streamName) => _FakeOrderedConsumer(
      client.jetStream(), streamName, OrderedConsumerConfig(), incoming.stream);
}

Message<dynamic> makeMessage(String subject, String payload, Client client,
    {int sid = 1}) {
  return Message<dynamic>(
      subject, sid, Uint8List.fromList(utf8.encode(payload)), client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildView(FakeJetStreamManager manager,
      {Listenable? reconnectSignal}) {
    return MaterialApp(
      home: Scaffold(
        body: JetStreamMessageView(
          streamName: 'ORDERS',
          manager: manager,
          reconnectSignal: reconnectSignal,
          onClose: () {},
        ),
      ),
    );
  }

  testWidgets(
      'prepending new messages while scrolled away keeps the viewport stable '
      'with no filter active (scroll offset is compensated)', (tester) async {
    final manager = FakeJetStreamManager();
    await tester.pumpWidget(buildView(manager));
    await tester.pump();

    // Fill well past one viewport (rows are a fixed 56px; the 600px test
    // surface shows ~10).
    for (var i = 0; i < 30; i++) {
      manager.incoming
          .add(makeMessage('orders.$i', 'payload $i', manager.client));
    }
    // One flush interval + a frame for the insert.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.textContaining('30 received'), findsOneWidget);

    // Scroll down two rows' worth.
    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller!;
    controller.jumpTo(112.0);
    await tester.pump();

    // Two new arrivals prepend above the viewport...
    manager.incoming.add(makeMessage('orders.n1', 'new 1', manager.client));
    manager.incoming.add(makeMessage('orders.n2', 'new 2', manager.client));
    await tester.pump(const Duration(milliseconds: 50));
    // ...and the post-frame compensation shifts the offset by exactly the
    // two prepended rows' height, so on-screen content doesn't move.
    await tester.pump();
    await tester.pump();

    expect(controller.offset, 112.0 + 2 * 56.0,
        reason: 'The scroll offset must shift by the prepended rows\' exact '
            'height so the messages on screen stay put');
  });

  testWidgets(
      'a reconnect signal auto-recovers a view stuck showing a Retry error, '
      'without needing a manual click', (tester) async {
    final manager = FakeJetStreamManager();
    final reconnectSignal = ValueNotifier<int>(0);

    await tester
        .pumpWidget(buildView(manager, reconnectSignal: reconnectSignal));
    await tester.pump();

    manager.incoming.addError(Exception('createConsumer: not connected'));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    // Simulate main.dart noticing a real reconnect -- no manual Retry tap.
    reconnectSignal.value++;
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Waiting for messages...'), findsOneWidget);
  });

  testWidgets(
      'a reconnect signal is a no-op when the view is not currently erroring',
      (tester) async {
    final manager = FakeJetStreamManager();
    final reconnectSignal = ValueNotifier<int>(0);

    await tester
        .pumpWidget(buildView(manager, reconnectSignal: reconnectSignal));
    await tester.pump();

    manager.incoming.add(makeMessage('orders.1', 'payload', manager.client));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.textContaining('1 received'), findsOneWidget);

    reconnectSignal.value++;
    await tester.pump();

    // Still showing the same message -- a healthy view wasn't reset/retried.
    expect(find.textContaining('1 received'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  group('wrapping and pinned fields', () {
    final longJson = jsonEncode({
      'id': 1,
      'note': 'n' * 600,
      'items': [
        {'sku': 'A1'},
        {'sku': 'B7'},
      ],
      'label': 'urgent',
    });

    Widget buildWithDisplay(
            FakeJetStreamManager manager, MessageListDisplay display) =>
        MaterialApp(
          home: Scaffold(
            body: JetStreamMessageView(
              streamName: 'ORDERS',
              manager: manager,
              onClose: () {},
              display: display,
            ),
          ),
        );

    testWidgets('multi-line rows wrap and show pinned values', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final manager = FakeJetStreamManager();
      await tester.pumpWidget(buildWithDisplay(
          manager,
          const MessageListDisplay(
              maxLines: 4, pinnedFields: ['label', 'items[*].sku'])));
      await tester.pump();

      manager.incoming.add(makeMessage('orders.a', longJson, manager.client));
      manager.incoming
          .add(makeMessage('orders.b', 'heartbeat', manager.client));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final tiles = tester
          .widgetList<LiveMessageRow>(find.byType(LiveMessageRow))
          .toList();
      // Newest first: the heartbeat, then the long order.
      expect(tiles[0].pins, isNull);
      expect(tiles[1].pins, isNotNull);
      expect(tiles[1].wrap!.lineCount, 4);
      expect(find.text('urgent'), findsOneWidget);
      expect(find.text('A1, B7'), findsOneWidget);
      expect(tester.getSize(find.byType(ListTile).at(1)).height,
          messageRowExtent(4, 14));
    });

    testWidgets(
        'prepending multi-line rows while scrolled away shifts by their '
        'real heights', (tester) async {
      final manager = FakeJetStreamManager();
      await tester.pumpWidget(
          buildWithDisplay(manager, const MessageListDisplay(maxLines: 3)));
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        manager.incoming
            .add(makeMessage('orders.$i', 'payload $i', manager.client));
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final controller =
          tester.widget<ListView>(find.byType(ExactExtentListView)).controller!;
      controller.jumpTo(112.0);
      await tester.pump();

      // One long (3-line) and one short arrival.
      manager.incoming.add(makeMessage('orders.n1', longJson, manager.client));
      manager.incoming.add(makeMessage('orders.n2', 'short', manager.client));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();

      expect(controller.offset,
          112.0 + messageRowExtent(3, 14) + messageRowExtent(1, 14));
    });

    testWidgets('Pin Fields… in the row menu reports the new pins',
        (tester) async {
      List<String>? changed;
      final manager = FakeJetStreamManager();
      await tester.pumpWidget(buildWithDisplay(manager,
          MessageListDisplay(onPinnedFieldsChanged: (pins) => changed = pins)));
      await tester.pump();
      manager.incoming.add(makeMessage('orders.a', longJson, manager.client));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin Fields…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pinFieldsRow_label')));
      await tester.pump();
      await tester.tap(find.text('Pin 1 Field'));
      await tester.pumpAndSettle();
      expect(changed, ['label']);
    });
  });
}
