import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/regex_text_highlight.dart';

import 'helpers/nats_test_app.dart';

/// Guards the fixed-height message rows (`_messageRowExtent` in
/// `lib/main.dart`) against clipping/overflow: because every row is now a
/// fixed height rather than sizing itself to its content, a row extent that
/// were too short for the row's own text + trailing controls would produce a
/// render overflow. This exercises the worst case — the maximum font size
/// (30, the Settings slider's `max`) with a long message, asserting no
/// exception is thrown during layout.
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

  // A long payload with several natural wrap points, so it exercises the
  // tallest a message row can get before it is clipped with an ellipsis.
  const longPayload =
      'this-is-a-deliberately-long-message-payload that should wrap across '
      'several lines at a large font size, exercising the tallest a message '
      'row can get before it is clipped with an ellipsis at the row extent';

  testWidgets(
      'a long message does not overflow the row extent at max font size',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    // Read in `initState` when `app.main()` runs inside `pumpConnectedApp`.
    await prefs.setDouble('messageFontSize', 30.0);

    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.row-extent.$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    publisher.pubString(subject, longPayload);
    await pumpUntil(
        tester, () => messageRowText(longPayload).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason:
            'a long message at the max font size must not overflow the fixed row extent');
  });

  testWidgets(
      'a long message does not overflow the row extent at max font size '
      'with timestamps on',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('messageFontSize', 30.0);

    // `showTimestamps` is passed directly to `pumpConnectedApp` (rather
    // than seeded beforehand, which would just be clobbered by its own
    // reset-to-default) so this app instance's very first
    // `loadMessageSettings` read picks it up.
    await pumpConnectedApp(tester, showTimestamps: true);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.row-extent-ts.$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    publisher.pubString(subject, longPayload);
    await pumpUntil(
        tester, () => messageRowText(longPayload).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason:
            'the thin per-row timestamp must not push a long message past '
            'the fixed row extent at the max font size');
  });

  testWidgets(
      'toggling Show Message Timestamps in Settings shows/hides a '
      'per-row HH:mm:ss text without changing the row extent',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.row-extent-toggle.$runId';
    final payload = 'timestamp-toggle-payload-$runId';

    final publisher = await connectPublisher();
    addTearDown(() => publisher.close());

    publisher.pubString(subject, payload);
    await pumpUntil(
        tester, () => messageRowText(payload).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    final timeOfDayPattern = RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3} (AM|PM)$');
    bool anyTimeRowShown() => find
        .byWidgetPredicate((w) =>
            w is Text && w.data != null && timeOfDayPattern.hasMatch(w.data!))
        .evaluate()
        .isNotEmpty;

    // Off by default.
    expect(anyTimeRowShown(), isFalse);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show Message Timestamps'));
    // The Switch that sits in the same Row as the "Show Message Timestamps"
    // label.
    final switchFinder = find.descendant(
        of: find.ancestor(
            of: find.text('Show Message Timestamps'), matching: find.byType(Row)),
        matching: find.byType(Switch));
    await tester.tap(switchFinder);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(anyTimeRowShown(), isTrue);
    expect(tester.takeException(), isNull,
        reason: 'the fixed row extent must not overflow once the timestamp '
            'is added to the row');

    // Toggle back off.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show Message Timestamps'));
    await tester.tap(switchFinder);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(anyTimeRowShown(), isFalse);
  });
}
