import 'dart:convert';

import 'package:dart_nats/dart_nats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';

import 'helpers/nats_test_app.dart';

/// Verifies queue-group subscriptions actually load-balance rather than
/// fan out, against a real, locally-running `nats-server` (see AGENTS.md
/// "Recipe E: Local JetStream Testing" for how to start one -- this test
/// only needs plain NATS, no `-js` flag required).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'two subscribers in the same queue group split delivery of a message burst',
      (tester) async {
    final uniqueSubject =
        'integration.queuegroup.${DateTime.now().microsecondsSinceEpoch}';
    const queueGroup = 'workers';

    await pumpConnectedApp(tester, subject: uniqueSubject);
    addTearDown(() => disconnectApp(tester));

    // Give the app's own (already-connected, queue-group-less) subscription
    // a queue group via the chip's edit affordance -- this exercises the
    // real live unsub+resub path (_updateQueueGroup in main.dart), not a
    // seeded pref.
    await tester.tap(find.text(uniqueSubject));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Queue group (optional)'),
        queueGroup);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // A second, bare dart_nats client joins the same queue group directly --
    // no existing integration test instantiates a second Client, so this is
    // new infrastructure, not an existing pattern to copy.
    final second = Client();
    await second.connect(Uri.parse('nats://127.0.0.1:4222'));
    var secondReceivedCount = 0;
    second.sub(uniqueSubject, queueGroup: queueGroup).stream.listen((_) {
      secondReceivedCount++;
    });
    addTearDown(() => second.forceClose());
    // `sub()` only writes the SUB command to the socket -- it doesn't wait
    // for the server to actually process it. Without this, there's no
    // enforced ordering between that write and the publisher's burst below
    // (they're on separate connections), so on a loaded runner the burst can
    // reach the server before this SUB does and those early messages are
    // dropped entirely rather than delivered to either queue member. `flush`
    // performs a ping/pong round trip, and NATS processes each connection's
    // commands in order, so its return guarantees the SUB already landed.
    await second.flush();

    // A third, independent bare client publishes a burst of uniquely-named
    // messages. 20 messages keeps the odds of every message randomly
    // landing on the same queue member (a false failure, not a real one)
    // astronomically small (2 * 0.5^20) while still finishing fast.
    final publisher = Client();
    await publisher.connect(Uri.parse('nats://127.0.0.1:4222'));
    addTearDown(() => publisher.forceClose());
    const messageCount = 20;
    for (var i = 0; i < messageCount; i++) {
      publisher.pub(uniqueSubject, utf8.encode('queue-group-test-$i'));
    }
    await publisher.flush();

    // No single positive UI condition to poll for here -- we're asserting a
    // *count* split across two processes, not a single row's presence --
    // so pump for a bounded window instead of pumpUntil.
    await pumpBriefly(tester, duration: const Duration(seconds: 3));

    Finder messageRowText(String payload) => find.byWidgetPredicate(
        (widget) => widget is RegexTextHighlight && widget.text == payload);

    var appReceivedCount = 0;
    for (var i = 0; i < messageCount; i++) {
      if (messageRowText('queue-group-test-$i').evaluate().isNotEmpty) {
        appReceivedCount++;
      }
    }

    // The definitive queue-group assertion: every message was delivered to
    // exactly one member, never both and never neither.
    expect(appReceivedCount + secondReceivedCount, messageCount);
    expect(appReceivedCount, lessThan(messageCount),
        reason: 'the app should not have received every message -- that '
            'would mean it was still fanning out rather than load-balancing');
    expect(secondReceivedCount, greaterThan(0),
        reason: 'the second queue member should have received some share '
            'of the burst');
  });
}
