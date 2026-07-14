import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/regex_text_highlight.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the JetStream "Browse Messages" view (`JetStreamMessageView`,
/// the ephemeral ordered-consumer tail) against a real, locally-running
/// JetStream-enabled `nats-server` (see AGENTS.md "Recipe E: Local
/// JetStream Testing"). This view was flagged untestable-via-fake back in
/// Milestone 1a (an `OrderedConsumer` is bound to a real `Client`) and was
/// still unexercised even after the real-server integration suite landed —
/// `jetstream_lifecycle_test.dart` tails a named consumer instead of using
/// this button.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The Filter/Find fields both set `hintText` and `labelText` to the same
  /// string, so `find.widgetWithText` on that text is ambiguous; their
  /// distinct prefix icons aren't. See the same helper in
  /// `live_messages_interactions_test.dart`.
  Finder fieldWithPrefixIcon(IconData icon) {
    return find.ancestor(
        of: find.byIcon(icon), matching: find.byType(TextFormField));
  }

  /// Matches the custom `RegexTextHighlight` widget the message list uses
  /// for row content — deliberately not `find.text()`, which also matches
  /// `EditableText` and double-counts every unstyled row via its internal
  /// `RichText`. See the same helper in `live_messages_interactions_test.dart`.
  Finder messageRowText(String payload) => find.byWidgetPredicate(
      (widget) => widget is RegexTextHighlight && widget.text == payload);

  testWidgets('Browse Messages shows published messages and its row menu works',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final streamName = 'it_browse_$runId';
    final payload = 'it-browse-payload-$runId';
    final payload2 = 'it-browse-payload-2-$runId';

    addTearDown(() async {
      // Best-effort cleanup in case an assertion above failed first.
      final leftoverStream = find.text(streamName);
      if (leftoverStream.evaluate().isEmpty) return;
      await tester.tap(leftoverStream);
      await tester.pumpAndSettle();
      final deleteStreamButton =
          find.widgetWithText(OutlinedButton, 'Delete Stream');
      if (deleteStreamButton.evaluate().isEmpty) return;
      await tester.tap(deleteStreamButton);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Delete');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.last);
        await tester.pumpAndSettle();
      }
    });

    // 1. Create a stream.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Stream'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Stream Name'), streamName);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subjects (comma-separated)'),
        '$streamName.>');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" created.').evaluate().isNotEmpty);
    await waitForSnackBarGone(tester);

    // 2. Publish two messages into it via the Live Messages tab (two so
    // Filter/Find below have something to distinguish).
    await tester.tap(find.text('Live Messages'));
    await tester.pumpAndSettle();
    Future<void> publishToStream(String data) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), '$streamName.created');
      await tester.enterText(find.widgetWithText(TextFormField, 'Data'), data);
      await tester.tap(find.text('Publish via JetStream (get delivery ack)'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntil(
          tester,
          () => find
              .textContaining('Published to stream "$streamName" at seq')
              .evaluate()
              .isNotEmpty);
      await waitForSnackBarGone(tester);
    }

    await publishToStream(payload);
    await publishToStream(payload2);

    // 3. Back to JetStream (re-select — dashboard state doesn't survive the
    // tab round trip, see jetstream_lifecycle_test.dart), then Browse.
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text(streamName).evaluate().isNotEmpty);
    await tester.tap(find.text(streamName));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Browse Messages'));
    await tester.pumpAndSettle();

    await pumpUntil(tester, () => find.text(payload2).evaluate().isNotEmpty);
    expect(find.textContaining('Browsing: $streamName'), findsOneWidget);
    expect(messageRowText(payload), findsOneWidget);
    expect(messageRowText(payload2), findsOneWidget);

    // 4. Filter narrows the list to matching messages only.
    await tester.enterText(fieldWithPrefixIcon(Icons.filter_list), payload2);
    await tester.pump();
    expect(messageRowText(payload2), findsOneWidget);
    expect(messageRowText(payload), findsNothing);

    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.filter_list),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();
    expect(messageRowText(payload), findsOneWidget);
    expect(messageRowText(payload2), findsOneWidget);

    // 5. Find highlights matches without hiding anything else.
    await tester.enterText(fieldWithPrefixIcon(Icons.search), payload2);
    await tester.pump();
    expect(messageRowText(payload), findsOneWidget);
    expect(messageRowText(payload2), findsOneWidget);

    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.search),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();

    // 6. Ctrl+F / Ctrl+Shift+F reach this view's own Find/Filter fields —
    // the app-wide shortcut handler in `lib/main.dart` is tab-aware and
    // routes to `JetStreamDashboardState.focusFindField()`/
    // `focusFilterField()` (which delegate to this view via a `GlobalKey`)
    // whenever the JetStream tab is showing Browse Messages, same as it
    // routes to the Live Messages tab's fields otherwise — see the same
    // shortcut assertions in `live_messages_interactions_test.dart`.
    bool fieldHasFocus(IconData icon) =>
        Focus.of(tester.element(fieldWithPrefixIcon(icon))).hasFocus;

    await tester.tap(fieldWithPrefixIcon(Icons.filter_list));
    await tester.pump();
    expect(fieldHasFocus(Icons.filter_list), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(fieldHasFocus(Icons.search), isTrue,
        reason: 'Ctrl+F should move focus to this view\'s Find field');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(fieldHasFocus(Icons.filter_list), isTrue,
        reason: 'Ctrl+Shift+F should move focus to this view\'s Filter field');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // Filter back down to a single row so the row-menu steps below (which
    // assert against `payload` specifically) have exactly one
    // `PopupMenuButton` to target.
    await tester.enterText(fieldWithPrefixIcon(Icons.filter_list), payload);
    await tester.pump();
    expect(messageRowText(payload), findsOneWidget);
    expect(messageRowText(payload2), findsNothing);

    // 7. Row menu: Detail opens the Message Detail dialog.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Message Detail'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // 8. Row menu: Copy copies the payload to the clipboard.
    final copiedData = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copiedData, contains(payload));

    // 9. Pause / Resume: a message published while paused must not appear
    // until Resume, and the badge should reflect it meanwhile. Publish via
    // a second, direct `dart_nats` client (rather than switching to the
    // Live Messages tab) since switching tabs would tear down this whole
    // Browse session — `JetStreamDashboard`'s state doesn't survive a trip
    // away from the JetStream tab, per the note in `AGENTS.md` Recipe F.
    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.filter_list),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();
    expect(messageRowText(payload), findsOneWidget);
    expect(messageRowText(payload2), findsOneWidget);
    final payload3 = 'it-browse-payload-3-$runId';
    final publisher = Client();
    await publisher.connect(Uri.parse(
        '${constants.defaultScheme}${constants.defaultHost}:${constants.defaultPort}'));
    addTearDown(() => publisher.close());

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Paused — no new messages yet'), findsOneWidget);

    publisher.pubString('$streamName.created', payload3);
    await tester.pump(const Duration(milliseconds: 300));
    expect(messageRowText(payload3), findsNothing);
    final pauseButtonRow = find.ancestor(
        of: find.byIcon(Icons.play_arrow), matching: find.byType(Row));
    expect(find.descendant(of: pauseButtonRow, matching: find.text('1')),
        findsOneWidget);
    expect(find.text('Paused — 1 new message buffered'), findsOneWidget);

    // Resume via the banner's own button this time (rather than the header
    // row's Pause/Resume icon), same as the equivalent Live Messages check
    // in `message_list_pause_test.dart` -- both surfaces drive the same
    // `_paused` state in `JetStreamMessageViewState`.
    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await pumpUntil(
        tester, () => messageRowText(payload3).evaluate().isNotEmpty);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.textContaining('Paused'), findsNothing);

    // 10. Delete/Clear empties the view (the underlying consumer keeps
    // running — not asserted here, just that the visible list resets).
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(messageRowText(payload), findsNothing);
    expect(messageRowText(payload2), findsNothing);
    expect(messageRowText(payload3), findsNothing);
    expect(find.text('0 received'), findsOneWidget);

    // 11. Back to stream details, then clean up.
    await tester.tap(find.byTooltip('Back to stream details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Stream'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpUntil(tester,
        () => find.text('Stream "$streamName" deleted.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text(streamName), findsNothing);
  });
}
