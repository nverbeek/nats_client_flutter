import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/exact_extent_list.dart';
import 'package:nats_client_flutter/live_message_row.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';
import 'package:window_manager/window_manager.dart';

import 'helpers/nats_test_app.dart';

/// Multi-line rows (Max Lines per Message > 1) against a real server: rows
/// of mixed heights must keep the viewport still while new messages arrive
/// above it, while a pinned column widens, and across a window resize. These
/// are exactly the cases variable-height rows used to get wrong.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder messageRowText(String payload) => find.byWidgetPredicate(
      (widget) => widget is RegexTextHighlight && widget.text == payload);

  Future<Client> connectPublisher() async {
    final client = Client();
    await client.connect(
      Uri.parse(
          '${constants.defaultScheme}${constants.defaultHost}:${constants.defaultPort}'),
    );
    return client;
  }

  /// Alternates short and long payloads so rows have different heights.
  String payload(String tag, int i) => i.isEven
      ? '$tag-$i'
      : jsonEncode({
          'tag': '$tag-$i',
          'note': 'n' * (150 + i * 20),
          'items': [
            {'sku': 'A$i'},
            {'sku': 'B$i'},
          ],
          'label': i % 3 == 0 ? 'urgent' : 'normal',
        });

  Future<void> scrollUntilVisible(WidgetTester tester, Finder target) async {
    // The default Scrollable finder is ambiguous here (the message list
    // isn't the only Scrollable), so drag the list in small steps.
    for (var attempt = 0;
        attempt < 40 && target.evaluate().isEmpty;
        attempt++) {
      await tester.drag(
          find.byType(ExactExtentListView), const Offset(0, -120));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(target, findsOneWidget);
  }

  testWidgets(
      'scrolled down, a burst is held (counted by the pill) and a resize '
      'keeps the view anchored; Jump to top lets the burst in', (tester) async {
    await pumpConnectedApp(tester,
        messageMaxLines: 4, pinnedFields: ['label', 'items[*].sku']);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.wrap.$runId';
    final tag = 'w$runId';
    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    for (var i = 0; i < 30; i++) {
      publisher.pubString(subject, payload(tag, i));
    }
    final last = messageRowText(payload(tag, 29));
    await pumpUntil(tester, () => last.evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    // Some long rows really are taller than the single-line extent.
    final tallRow = tester.getSize(find.ancestor(
        of: messageRowText(payload(tag, 29)), matching: find.byType(ListTile)));
    expect(tallRow.height, greaterThan(56));
    expect(find.byType(PinnedFieldCells), findsWidgets);

    // Scroll down to an older row in the middle of the list.
    final anchor = messageRowText(payload(tag, 11));
    await scrollUntilVisible(tester, anchor);
    final yBefore = tester.getTopLeft(anchor).dy;

    // 1. A burst of mixed-height rows, plus a much longer pinned value,
    //    arrives while scrolled down: held, so nothing moves.
    for (var i = 0; i < 25; i++) {
      publisher.pubString(subject, payload('$tag-burst', i));
    }
    final longLabel = jsonEncode({
      'label': 'a-much-longer-label-value-than-before',
      'note': 'z' * 300,
    });
    publisher.pubString(subject, longLabel);
    await pumpUntil(tester, () => find.text('26 new').evaluate().isNotEmpty);
    await tester.pump();
    expect(anchor, findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, moreOrLessEquals(yBefore, epsilon: 1),
        reason: 'held messages must not move the row the user is looking at');
    expect(messageRowText(longLabel), findsNothing);

    // 2. A window resize changes every row's wrap.
    final originalSize = await windowManager.getSize();
    addTearDown(() => windowManager.setSize(originalSize));
    await windowManager
        .setSize(Size(originalSize.width - 220, originalSize.height));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(anchor, findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, moreOrLessEquals(yBefore, epsilon: 1),
        reason: 'a resize must keep the first visible row anchored');
    expect(tester.takeException(), isNull);

    // 3. The pill jumps to the top and lets the held messages in.
    await tester.tap(find.byKey(const ValueKey('heldMessagesPill')));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byType(ExactExtentListView),
        matching: find.byType(Scrollable)));
    expect(scrollable.position.pixels, 0);
    expect(find.byTooltip('Jump to top'), findsNothing);
    expect(find.byKey(const ValueKey('heldMessagesPill')), findsNothing);
    expect(messageRowText(longLabel), findsOneWidget);
  });

  testWidgets('a hidden subject removes the chips; one line keeps 56px rows',
      (tester) async {
    await pumpConnectedApp(tester, showSubjectChip: false);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.wrap.hidden.$runId';
    final text = payload('h$runId', 1);
    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    publisher.pubString(subject, text);
    await pumpUntil(tester, () => messageRowText(text).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    final row = find.ancestor(
        of: messageRowText(text), matching: find.byType(LiveMessageRow));
    expect(find.descendant(of: row, matching: find.byType(Chip)), findsNothing);
    expect(
        tester
            .getSize(find.ancestor(
                of: messageRowText(text), matching: find.byType(ListTile)))
            .height,
        56);
  });

  testWidgets(
      'under a fast stream of mixed-height rows: a fling coasts to a stop '
      'instead of running to the bottom, Jump to top always lands at the '
      'top, and the scroll range only changes when messages arrive',
      (tester) async {
    await pumpConnectedApp(tester,
        messageMaxLines: 5, pinnedFields: ['label', 'items[*].sku']);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.wrap.fast.$runId';
    final tag = 'f$runId';
    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    for (var i = 0; i < 300; i++) {
      publisher.pubString(subject, payload(tag, i));
    }
    await pumpUntil(
        tester, () => messageRowText(payload(tag, 299)).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    ScrollPosition position() => tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(ExactExtentListView),
            matching: find.byType(Scrollable)))
        .position;

    // 1. Paused (nothing arriving): drag through the list. The scroll range
    //    must not change, or the scrollbar thumb jumps.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    final range = position().maxScrollExtent;
    for (var step = 0; step < 25; step++) {
      await tester.drag(
          find.byType(ExactExtentListView), const Offset(0, -400));
      await tester.pump();
      expect(position().maxScrollExtent, range,
          reason: 'scroll range changed while scrolling (step $step)');
    }
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    // 2. A steady fast stream while scrolled down; Jump to top must win
    //    every time, even when a flush lands right before the tap.
    var publishing = true;
    var n = 0;
    Future<void> stream() async {
      while (publishing) {
        for (var k = 0; k < 5; k++) {
          publisher.pubString(subject, payload('$tag-live', n++));
        }
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    }

    final streaming = stream();
    addTearDown(() => publishing = false);

    // A fling while messages pour in coasts and stops on its own: nothing is
    // inserted above (or trimmed below) a scrolled-down list.
    await tester.fling(
        find.byType(ExactExtentListView), const Offset(0, -600), 2500);
    var last = position().pixels;
    var stillFrames = 0;
    for (var f = 0; f < 240 && stillFrames < 20; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = position().pixels;
      stillFrames = (now - last).abs() < 0.5 ? stillFrames + 1 : 0;
      last = now;
    }
    expect(stillFrames, 20, reason: 'the fling never came to rest');
    expect(last, greaterThan(600), reason: 'the fling was cut short');
    expect(last, lessThan(position().maxScrollExtent),
        reason: 'the fling ran away to the bottom');
    expect(find.byKey(const ValueKey('heldMessagesPill')), findsOneWidget);
    for (var round = 0; round < 15; round++) {
      await tester.drag(
          find.byType(ExactExtentListView), const Offset(0, -1500));
      for (var f = 0; f < 3 + round % 4; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(position().pixels, greaterThan(0));
      await tester.tap(find.byTooltip('Jump to top'));
      for (var f = 0; f < 6; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(position().pixels, 0,
          reason: 'Jump to top did not stay at the top (round $round)');
    }
    publishing = false;
    await streaming;
    expect(tester.takeException(), isNull);
  });
}
