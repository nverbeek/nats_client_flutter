import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/regex_text_highlight.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the Live Messages tab's Pause/Resume control and the
/// scroll-position-stable insert behind it (Milestone 6 in ROADMAP.md — see
/// the `reverse: true` + sliver/data-index mapping comment on the
/// `ListView.builder` in `lib/main.dart`'s `_buildLiveMessagesTab`) against
/// a real, locally-running `nats-server` (see AGENTS.md "Recipe E: Local
/// JetStream Testing"). Bursts are published via a second, direct
/// `dart_nats` client rather than the app's own Send dialog — both because
/// it's far faster than driving the dialog N times, and because it's a
/// more realistic stand-in for "an external, fast-moving publisher" than
/// self-sends.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder messageRowText(String payload) => find.byWidgetPredicate(
      (widget) => widget is RegexTextHighlight && widget.text == payload);

  Color? tileColorOf(WidgetTester tester, String payload) {
    final tile = tester.widget<ListTile>(find.ancestor(
        of: messageRowText(payload), matching: find.byType(ListTile)));
    return tile.tileColor;
  }

  Future<Client> connectPublisher() async {
    final client = Client();
    await client.connect(
      Uri.parse(
          '${constants.defaultScheme}${constants.defaultHost}:${constants.defaultPort}'),
    );
    return client;
  }

  testWidgets(
      'Pause freezes the list and buffers arrivals; Resume reveals them',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.pause.$runId';
    final payload = 'it-pause-payload-$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    // 1. Pause.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // The paused banner should appear directly above the list as soon as
    // Pause is tapped, before any message has arrived to buffer.
    expect(find.text('Paused — no new messages yet'), findsOneWidget);

    // 2. A message arrives while paused: it must not appear yet, but the
    // Pause button's buffered-count pill -- and the banner above the list --
    // should reflect it once the flush timer (see `_incomingFlushInterval`
    // in main.dart) has had a chance to run.
    publisher.pubString(subject, payload);
    await tester.pump(const Duration(milliseconds: 300));
    expect(messageRowText(payload), findsNothing);
    final pauseButtonRow = find.ancestor(
        of: find.byIcon(Icons.play_arrow), matching: find.byType(Row));
    expect(find.descendant(of: pauseButtonRow, matching: find.text('1')),
        findsOneWidget);
    expect(find.text('Paused — 1 new message buffered'), findsOneWidget);

    // 3. Resume reveals it.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await pumpUntil(
        tester, () => messageRowText(payload).evaluate().isNotEmpty);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.textContaining('Paused'), findsNothing,
        reason: 'the banner must disappear once resumed');
  });

  testWidgets('the banner\'s own Resume button resumes the list',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.pause-banner-resume.$runId';
    final payload = 'it-pause-banner-resume-payload-$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    publisher.pubString(subject, payload);
    await pumpUntil(
        tester,
        () =>
            find.text('Paused — 1 new message buffered').evaluate().isNotEmpty);
    expect(messageRowText(payload), findsNothing);

    // Resuming via the banner's own button (rather than the toolbar's
    // Pause/Resume control) should reveal the buffered message and put the
    // toolbar button back into its Pause state too -- both surfaces reflect
    // the same underlying `messagesPaused` state.
    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await pumpUntil(
        tester, () => messageRowText(payload).evaluate().isNotEmpty);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.textContaining('Paused'), findsNothing);
  });

  testWidgets(
      'a wide buffered count ("1.2k"-style) does not overflow the Pause '
      'button', (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.pause-wide-count.$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // A single-digit buffered count (e.g. "1") is too narrow to expose an
    // overflow that only shows up once the pill is wide enough — this is
    // exactly the gap that let a real "overflowed by X pixels" error reach
    // a user despite this file's other Pause/Resume test passing. 1,200
    // renders as "1.2k".
    for (var i = 0; i < 1200; i++) {
      publisher.pubString(subject, 'it-pause-wide-$i-$runId');
    }
    await pumpUntil(
      tester,
      () {
        final pauseButtonRow = find.ancestor(
            of: find.byIcon(Icons.play_arrow), matching: find.byType(Row));
        return find
            .descendant(of: pauseButtonRow, matching: find.text('1.2k'))
            .evaluate()
            .isNotEmpty;
      },
      timeout: const Duration(seconds: 20),
    );
    expect(tester.takeException(), isNull,
        reason: 'the Pause button\'s fixed-width slot must be wide enough '
            'for a realistic wide count, not just a single digit');
    expect(find.text('Paused — 1.2k new messages buffered'), findsOneWidget,
        reason: 'the banner should use the same compact count formatting '
            'as the toolbar pill');
  });

  testWidgets(
      'a fast burst of messages does not move the row the user is looking at',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.burst.$runId';
    final anchorPayload = 'it-burst-anchor-$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    // Publish the anchor first, then bury it under 20 newer "filler"
    // messages (newest-first means those render above it) so scrolling
    // down brings the anchor into view without scrolling past it.
    publisher.pubString(subject, anchorPayload);
    for (var i = 0; i < 20; i++) {
      publisher.pubString(subject, 'it-burst-filler-$i-$runId');
    }
    await pumpUntil(
        tester,
        () =>
            messageRowText('it-burst-filler-19-$runId').evaluate().isNotEmpty);

    // `scrollUntilVisible`'s default `Scrollable` finder is ambiguous here
    // (the message list isn't the only Scrollable in the tree), so scroll
    // manually in small steps instead.
    for (var attempt = 0;
        attempt < 30 && messageRowText(anchorPayload).evaluate().isEmpty;
        attempt++) {
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(messageRowText(anchorPayload), findsOneWidget,
        reason: 'should have scrolled far enough to bring the anchor row '
            'into view');
    final yBefore = tester.getTopLeft(messageRowText(anchorPayload)).dy;
    final colorBefore = tileColorOf(tester, anchorPayload);

    // Now a fast burst arrives above it — this is the scenario that used
    // to make the list "run away" from under a fast-moving subject. An odd
    // count is deliberate: with the old sliver-index-based row-banding
    // scheme (before the `reverse: true` rework), an odd shift is exactly
    // what flipped every row's stripe color even though the row itself
    // hadn't moved — an even shift wouldn't have exposed that bug.
    for (var i = 0; i < 29; i++) {
      publisher.pubString(subject, 'it-burst-new-$i-$runId');
    }
    // Give the batching flush + scroll-compensation post-frame callback
    // time to run.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(messageRowText(anchorPayload), findsOneWidget,
        reason: 'the anchor row should still be on screen, not scrolled '
            'out of view by the burst');
    final yAfter = tester.getTopLeft(messageRowText(anchorPayload)).dy;
    // `moreOrLessEquals` rather than exact equality: real ListTile layout
    // can differ by float rounding noise (~1e-13px) between the two
    // measurements, which is imperceptible but not bit-exact.
    expect(yAfter, moreOrLessEquals(yBefore, epsilon: 0.5),
        reason: 'a burst of new messages arriving while scrolled away from '
            'the top must not move the row the user was looking at');
    expect(tileColorOf(tester, anchorPayload), equals(colorBefore),
        reason: 'row banding must be tied to each message, not its current '
            'list index — an odd-sized burst shifting every index must not '
            'flip the anchor row\'s stripe color');
  });
}
