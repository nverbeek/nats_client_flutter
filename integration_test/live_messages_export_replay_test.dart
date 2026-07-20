import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/main.dart' as app;
import 'package:nats_client_flutter/message_export.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';
import 'package:nats_client_flutter/replay_banner.dart';
import 'package:nats_client_flutter/replay_config_dialog.dart';

import 'helpers/nats_test_app.dart';

/// Exercises Milestone 22's Export/Replay round trip against a real, locally
/// running `nats-server` (see AGENTS.md "Recipe E: Local JetStream Testing"
/// -- a plain core-NATS server is sufficient here, JetStream isn't involved).
///
/// Neither Export's save-file step nor Replay's open-file step goes through
/// a real OS dialog -- like Object Store's Upload/Download
/// (`object_store_lifecycle_test.dart`), that plumbing isn't automatable.
/// `MyHomePage` has no constructor-level injection seam for either callback
/// (deliberately -- see the design notes in `lib/main.dart`), so this grabs
/// the running `State` through the public `MyHomePage` type and assigns its
/// public-but-unnamed-outside-this-library `saveExportedMessages`/
/// `replayPickFileOverride` fields dynamically. `ReplayConfigDialog` itself
/// already accepts an injected `pickFile` directly and is covered without a
/// live server in `test/replay_config_dialog_test.dart`; this file is only
/// responsible for the parts that need a real connection: messages actually
/// landing back on the wire.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder messageRowText(String payload) => find.byWidgetPredicate(
      (widget) => widget is RegexTextHighlight && widget.text == payload);

  Future<void> sendCoreMessage(
      WidgetTester tester, String subject, String data) async {
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'), subject);
    await tester.enterText(find.widgetWithText(TextFormField, 'Data'), data);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await pumpUntil(tester, () => find.text(data).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Export Selected round-trips through Replay, honoring repeat count/interval',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subjectA = 'it.exportreplay.a.$runId';
    final subjectB = 'it.exportreplay.b.$runId';
    final payloadA = 'it-exportreplay-payload-a-$runId';
    final payloadB = 'it-exportreplay-payload-b-$runId';

    await sendCoreMessage(tester, subjectA, payloadA);
    await sendCoreMessage(tester, subjectB, payloadB);
    expect(messageRowText(payloadA), findsOneWidget);
    expect(messageRowText(payloadB), findsOneWidget);

    final state = tester.state(find.byType(app.MyHomePage));
    Uint8List? exportedBytes;
    (state as dynamic).saveExportedMessages =
        (String suggestedName, Uint8List bytes) async {
      exportedBytes = bytes;
    };

    // Shift+Click range-select both messages (newest first on screen: B,
    // then A), then Export Selected from the toolbar.
    Finder rowFor(String payload) => find.ancestor(
        of: messageRowText(payload), matching: find.byType(ListTile));
    await tester.tap(messageRowText(payloadB));
    final selectedColor =
        Theme.of(tester.element(rowFor(payloadB))).colorScheme.inversePrimary;
    await pumpUntil(
        tester,
        () =>
            tester.widget<ListTile>(rowFor(payloadB)).tileColor ==
            selectedColor,
        timeout: const Duration(seconds: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(messageRowText(payloadA));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    await tester.tap(find.byTooltip('Export messages'));
    await tester.pumpAndSettle();
    expect(find.text('Export Selected (2)'), findsOneWidget);
    await tester.tap(find.text('Export Selected (2)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Export 2 selected message(s) to a file?'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Export'));
    await tester.pumpAndSettle();

    expect(find.text('Exported 2 message(s).'), findsOneWidget);
    await waitForSnackBarGone(tester);

    expect(exportedBytes, isNotNull);
    final parsed = parseExportedMessagesNdjson(utf8.decode(exportedBytes!));
    expect(parsed.hasErrors, isFalse);
    expect(parsed.messages, hasLength(2));
    // On-screen top-to-bottom order (newest first): B, then A.
    expect(parsed.messages[0].subject, subjectB);
    expect(utf8.decode(parsed.messages[0].payload), payloadB);
    expect(parsed.messages[1].subject, subjectA);
    expect(utf8.decode(parsed.messages[1].payload), payloadA);

    // Replay the exported file back onto the server: repeatCount 1 means
    // two total passes, separated by a small, measurable repeatInterval.
    (state as dynamic).replayPickFileOverride =
        () async => (exportedBytes!, 'export.ndjson');

    await tester.tap(find.byTooltip('Replay messages from file'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Choose File'));
    await tester.pumpAndSettle();
    expect(find.text('export.ndjson'), findsOneWidget);
    expect(find.text('2 message(s) parsed.'), findsOneWidget);

    final fields = find.descendant(
        of: find.byType(ReplayConfigDialog),
        matching: find.byType(TextFormField));
    await tester.enterText(fields.at(0), '0'); // message interval
    await tester.enterText(fields.at(1), '1'); // repeat count
    await tester.enterText(fields.at(2), '500'); // repeat interval
    await tester.pumpAndSettle();

    final replayStarted = DateTime.now();
    await tester.tap(find.widgetWithText(TextButton, 'Start Replay'));
    // Deliberately a single `pump()`, not `pumpAndSettle()` -- the replay
    // loop's real `Future.delayed` waits (repeat interval) keep scheduling
    // frames via `setState` for as long as it runs, so `pumpAndSettle()`
    // here would block until the *entire* replay (all passes) finishes
    // instead of returning once the dialog closes and the banner appears.
    // `_startReplay` -> `_runReplay` does its first `setState` before any
    // `await`, so one frame is enough for the banner to show up.
    await tester.pump();

    expect(find.byType(ReplayBanner), findsOneWidget);

    // Both passes replay both messages, so each payload should now appear
    // 3 times total (1 original send + 2 replayed copies).
    await pumpUntil(
        tester, () => messageRowText(payloadA).evaluate().length >= 3,
        timeout: const Duration(seconds: 20));
    await pumpUntil(
        tester, () => messageRowText(payloadB).evaluate().length >= 3,
        timeout: const Duration(seconds: 20));
    final elapsed = DateTime.now().difference(replayStarted);
    expect(elapsed.inMilliseconds, greaterThanOrEqualTo(400),
        reason: 'the 500ms repeat interval between the two passes should '
            'be roughly honored (generous tolerance for test overhead)');

    await pumpUntil(tester, () => find.byType(ReplayBanner).evaluate().isEmpty,
        timeout: const Duration(seconds: 10));
  });

  testWidgets('Stop halts a running replay before it finishes', (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subject = 'it.exportreplay.cancel.$runId';

    // Built directly rather than captured through the UI -- Replay only
    // needs a valid NDJSON file, not a message that was actually received.
    final messages = List.generate(
      6,
      (i) => ExportedMessage(
        subject: subject,
        payload: Uint8List.fromList(utf8.encode('cancel-payload-$i-$runId')),
      ),
    );
    final bytes =
        Uint8List.fromList(utf8.encode(encodeExportedMessagesNdjson(messages)));

    final state = tester.state(find.byType(app.MyHomePage));
    (state as dynamic).replayPickFileOverride =
        () async => (bytes, 'cancel.ndjson');

    await tester.tap(find.byTooltip('Replay messages from file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Choose File'));
    await tester.pumpAndSettle();
    expect(find.text('6 message(s) parsed.'), findsOneWidget);

    final fields = find.descendant(
        of: find.byType(ReplayConfigDialog),
        matching: find.byType(TextFormField));
    // A large enough per-message interval that Stop has time to land
    // mid-run rather than the whole replay finishing before it's tapped.
    await tester.enterText(fields.at(0), '2000');
    await tester.enterText(fields.at(1), '0');
    await tester.enterText(fields.at(2), '0');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Start Replay'));
    await tester.pumpAndSettle();
    expect(find.byType(ReplayBanner), findsOneWidget);

    await pumpUntil(
        tester,
        () => find
            .textContaining('cancel-payload-0-$runId')
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 10));

    await tester.tap(find.widgetWithText(TextButton, 'Stop'));
    await tester.pump();

    final countAfterStop =
        find.textContaining('cancel-payload').evaluate().length;
    await pumpBriefly(tester, duration: const Duration(seconds: 3));
    expect(
        find.textContaining('cancel-payload').evaluate().length, countAfterStop,
        reason: 'no further replayed messages should arrive after Stop');
    expect(find.byType(ReplayBanner), findsNothing);
  });
}
