import 'dart:convert';

import 'package:dart_nats/dart_nats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';

import 'helpers/nats_test_app.dart';

/// Verifies the chip-based Subjects row against a real, locally-running
/// `nats-server` (see AGENTS.md "Recipe E: Local JetStream Testing" for how
/// to start one -- this test only needs plain NATS, no `-js` flag
/// required): adding a second subscription live-subscribes it, each
/// subscription's messages get a distinct color indicator, and removing a
/// chip live-unsubscribes it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder messageRowText(String payload) => find.byWidgetPredicate(
      (widget) => widget is RegexTextHighlight && widget.text == payload);

  Color barColorFor(Finder rowPayloadFinder) {
    // The color bar is a sibling of the ListTile (not a descendant of it --
    // see main.dart's itemBuilder), both under the row's own keyed Material.
    // Match on `key is ObjectKey` specifically: ListTile may have its own
    // internal Material/InkWell for tap ripples, which would otherwise be a
    // *closer* (wrong) ancestor match than the row-level one we actually want.
    final row = find.ancestor(
        of: rowPayloadFinder,
        matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.key is ObjectKey));
    final bar = find.descendant(
        of: row.first,
        matching: find.byKey(const ValueKey('subscriptionColorBar')));
    final container = bar.evaluate().single.widget as Container;
    return container.color!;
  }

  testWidgets(
      'a second subscription added via the chip UI live-subscribes and '
      'gets a distinct message-row color', (tester) async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final subjectA = 'integration.chips.a.$ts';
    final subjectB = 'integration.chips.b.$ts';

    await pumpConnectedApp(tester, subject: subjectA);
    addTearDown(() => disconnectApp(tester));

    // Add a second subscription through the chip row's "+" -- exercises the
    // real live-subscribe path (_addSubscription in main.dart), not a
    // seeded pref. Target by key, not find.byTooltip/find.byType: the "+"
    // button is built twice -- once for real, once inside SubjectChipsRow's
    // invisible offstage width-measurement pass (see subject_chips_row.dart)
    // -- and generic finders match both copies since Offstage only affects
    // painting/hit-testing, not the widget tree finders walk.
    await tester
        .tap(find.byKey(const ValueKey('subjectChipsAddButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'), subjectB);
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    final publisher = Client();
    await publisher.connect(Uri.parse('nats://127.0.0.1:4222'));
    addTearDown(() => publisher.forceClose());

    final payloadA = 'chips-payload-a-$ts';
    final payloadB = 'chips-payload-b-$ts';
    publisher.pub(subjectA, utf8.encode(payloadA));
    publisher.pub(subjectB, utf8.encode(payloadB));
    await publisher.flush();

    await pumpUntil(
      tester,
      () =>
          messageRowText(payloadA).evaluate().isNotEmpty &&
          messageRowText(payloadB).evaluate().isNotEmpty,
    );

    final colorA = barColorFor(messageRowText(payloadA));
    final colorB = barColorFor(messageRowText(payloadB));
    expect(colorA, isNot(equals(colorB)));

    // Remove subjectB and confirm no further messages for it arrive. These
    // long, unique-timestamped subject strings may or may not fit directly
    // as a chip at the real window's width -- if they don't, subjectB has
    // collapsed into the "+N more" overflow chip, and removal has to go
    // through the manager dialog instead of a direct chip delete icon.
    // Both paths call the exact same _removeSubscription in main.dart, so
    // either is a valid way to exercise the live-unsubscribe wiring.
    final directChipB = find.ancestor(
        of: find.text(subjectB), matching: find.byType(InputChip));
    if (directChipB.evaluate().isNotEmpty) {
      await tester.tap(find.descendant(
          of: directChipB, matching: find.byIcon(Icons.clear)));
    } else {
      await tester.tap(find.textContaining('more'));
      await tester.pumpAndSettle();
      final managerRow =
          find.ancestor(of: find.text(subjectB), matching: find.byType(Row));
      final removeTooltip = find.descendant(
          of: managerRow, matching: find.byTooltip('Remove subscription'));
      // Tap the ancestor IconButton, not the Tooltip wrapper itself -- see
      // the comment on the "Add subscription" tap above.
      await tester.tap(find.ancestor(
          of: removeTooltip, matching: find.byType(IconButton)));
    }
    await tester.pumpAndSettle();

    final payloadB2 = 'chips-payload-b2-$ts';
    publisher.pub(subjectB, utf8.encode(payloadB2));
    await publisher.flush();

    // No positive condition to poll for -- asserting absence -- so pump for
    // a bounded window instead of pumpUntil.
    await pumpBriefly(tester, duration: const Duration(seconds: 3));

    expect(messageRowText(payloadB2), findsNothing);
  });
}
