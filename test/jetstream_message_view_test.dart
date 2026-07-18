import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/jetstream_manager.dart';
import 'package:nats_client_flutter/jetstream_message_view.dart';

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

  Widget buildView(FakeJetStreamManager manager) {
    return MaterialApp(
      home: Scaffold(
        body: JetStreamMessageView(
          streamName: 'ORDERS',
          manager: manager,
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
      manager.incoming.add(makeMessage('orders.$i', 'payload $i',
          manager.client));
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
}
