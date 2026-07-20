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
    final secondReceivedIndices = <int>{};
    second.sub(uniqueSubject, queueGroup: queueGroup).stream.listen((msg) {
      final match = RegExp(r'^queue-group-test-(\d+)$').firstMatch(msg.string);
      if (match != null) secondReceivedIndices.add(int.parse(match.group(1)!));
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
    //
    // This only covers `second`'s own SUB, though -- the app's live
    // unsub+resub a few lines up (via the chip edit above) has no equivalent
    // ack this test can wait on, since that connection is private to the
    // app's State and NATS itself doesn't ack SUB. So a message published
    // immediately after this point could still race the app's resubscribe
    // and land on the server before the app's new queue membership does,
    // getting silently dropped (delivered to neither member) rather than
    // just skewing the split. The retry loop below absorbs that: any index
    // dropped this way simply gets republished next round, once real time
    // has passed and both members are unquestionably registered.
    await second.flush();

    // A third, independent bare client publishes the burst of uniquely-named
    // messages. 20 messages keeps the odds of every message randomly landing
    // on the same queue member (a false failure, not a real one)
    // astronomically small (2 * 0.5^20) while still finishing fast.
    final publisher = Client();
    await publisher.connect(Uri.parse('nats://127.0.0.1:4222'));
    addTearDown(() => publisher.forceClose());
    const messageCount = 20;

    Finder messageRowText(String payload) => find.byWidgetPredicate(
        (widget) => widget is RegexTextHighlight && widget.text == payload);

    final appReceivedIndices = <int>{};
    var missing = {for (var i = 0; i < messageCount; i++) i};
    const maxAttempts = 5;
    for (var attempt = 1;
        attempt <= maxAttempts && missing.isNotEmpty;
        attempt++) {
      for (final i in missing) {
        publisher.pub(uniqueSubject, utf8.encode('queue-group-test-$i'));
      }
      await publisher.flush();

      // No single positive UI condition to poll for here -- we're asserting
      // a *count* split across two processes, not a single row's presence --
      // so pump for a bounded window instead of pumpUntil.
      await pumpBriefly(tester, duration: const Duration(seconds: 3));

      for (final i in missing.toList()) {
        if (messageRowText('queue-group-test-$i').evaluate().isNotEmpty) {
          appReceivedIndices.add(i);
        }
      }
      missing = missing
          .difference(appReceivedIndices)
          .difference(secondReceivedIndices);
    }

    // Give up loudly rather than silently passing/hanging: if messages are
    // still missing after several rounds each separated by real elapsed
    // time, that's a genuine delivery bug, not the startup race this retry
    // loop exists to absorb.
    expect(missing, isEmpty,
        reason: 'these indices were never delivered to either queue member '
            'after $maxAttempts attempts: $missing');

    // The definitive queue-group assertion: every message was delivered to
    // exactly one member, never both and never neither. "Neither" is
    // already ruled out by the `missing` check above; a plain sum-equality
    // check for "never both" would be fragile here, since a retried index
    // whose original delivery only *looked* lost (arrived just after that
    // round's window closed) can legitimately land on both members once
    // retried -- checking the intersection directly still catches a true
    // fan-out bug without being tripped up by that.
    final deliveredToBoth =
        appReceivedIndices.intersection(secondReceivedIndices);
    expect(deliveredToBoth, isEmpty,
        reason: 'these indices were delivered to both queue members, which '
            'means the subscription is fanning out rather than '
            'load-balancing: $deliveredToBoth');
    expect(appReceivedIndices.length, lessThan(messageCount),
        reason: 'the app should not have received every message -- that '
            'would mean it was still fanning out rather than load-balancing');
    expect(secondReceivedIndices.length, greaterThan(0),
        reason: 'the second queue member should have received some share '
            'of the burst');
  });
}
