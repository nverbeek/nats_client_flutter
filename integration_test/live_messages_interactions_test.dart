import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';
import 'package:nats_client_flutter/send_message_dialog.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the Live Messages tab's daily-use controls against a real,
/// locally-running `nats-server` (see AGENTS.md "Recipe E: Local JetStream
/// Testing") — Filter, Find, the per-row popup menu (Copy/Detail/Replay/
/// Edit & Send/Reply To), and the keyboard shortcuts. None of this is
/// widget-testable in isolation: `MyHomePage` constructs its own `Client()`
/// internally with no injection point for a fake, and these controls only
/// mean anything against messages that actually arrived over a real
/// connection.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The Filter/Find fields both set `hintText` and `labelText` to the same
  /// string, so `find.widgetWithText` on that text is ambiguous; their
  /// distinct prefix icons aren't. `TextFormField` doesn't expose its
  /// `decoration` as a field (only as a constructor param consumed
  /// internally), so locate it via its prefix icon's ancestor instead.
  Finder fieldWithPrefixIcon(IconData icon) {
    return find.ancestor(
        of: find.byIcon(icon), matching: find.byType(TextFormField));
  }

  /// Matches the custom `RegexTextHighlight` widget the message list uses
  /// for row content, keyed off its own `text` property — deliberately not
  /// `find.text()`, which also matches `EditableText` (a Send Message
  /// dialog field can transiently hold the same string as a payload already
  /// in the list) and, less obviously, would double-count every row even
  /// without that: a plain `Text` widget always builds its own internal
  /// `RichText` as an implementation detail, so a predicate checking both
  /// `Text` and `RichText` matches each unstyled row twice.
  Finder messageRowText(String payload) => find.byWidgetPredicate(
      (widget) => widget is RegexTextHighlight && widget.text == payload);

  testWidgets(
      'Filter, Find, row menu actions, and keyboard shortcuts all work',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subjectA = 'it.live.a.$runId';
    final subjectB = 'it.live.b.$runId';
    final payloadA = 'it-live-payload-a-$runId';
    final payloadB = 'it-live-payload-b-$runId';

    Future<void> sendCoreMessage(String subject, String data) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), subject);
      await tester.enterText(find.widgetWithText(TextFormField, 'Data'), data);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntil(tester, () => find.text(data).evaluate().isNotEmpty);
      // Unlike the JetStream publish flow, a core send shows no snackbar to
      // incidentally wait out the dialog's exit animation — settle
      // explicitly so it can't still be absorbing taps over the toolbar
      // underneath for the next action.
      await tester.pumpAndSettle();
    }

    await sendCoreMessage(subjectA, payloadA);
    await sendCoreMessage(subjectB, payloadB);
    expect(messageRowText(payloadA), findsOneWidget);
    expect(messageRowText(payloadB), findsOneWidget);

    // 1. Filter narrows the list to matching messages only.
    await tester.enterText(fieldWithPrefixIcon(Icons.filter_list), payloadA);
    await tester.pump();
    expect(messageRowText(payloadA), findsOneWidget);
    expect(messageRowText(payloadB), findsNothing);

    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.filter_list),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();
    expect(messageRowText(payloadB), findsOneWidget);

    // 2. Find highlights matches without hiding anything else.
    await tester.enterText(fieldWithPrefixIcon(Icons.search), payloadA);
    await tester.pump();
    expect(messageRowText(payloadA), findsOneWidget);
    expect(messageRowText(payloadB), findsOneWidget);

    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.search),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();

    // 3. Row popup menu: Copy.
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

    Finder rowFor(String payload) => find.ancestor(
        of: messageRowText(payload), matching: find.byType(ListTile));
    Finder popupMenuFor(String payload) => find.descendant(
        of: rowFor(payload).first,
        matching: find.byType(PopupMenuButton<String>));

    await tester.tap(popupMenuFor(payloadA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copiedData, contains(payloadA));
    expect(find.text('Copied to clipboard!'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 4. Row popup menu: Detail.
    await tester.tap(popupMenuFor(payloadA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Message Detail'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // 5. Row popup menu: Reply To with no replyTo shows a snackbar.
    await tester.tap(popupMenuFor(payloadA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply To'));
    await tester.pumpAndSettle();
    expect(find.text('This message has no replyTo subject'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 6. Row popup menu: Replay re-publishes the same subject/data, so a
    // second copy of the message arrives (the app is subscribed to '>').
    await tester.tap(popupMenuFor(payloadA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay'));
    await pumpUntil(
        tester, () => messageRowText(payloadA).evaluate().length >= 2);
    expect(messageRowText(payloadA), findsNWidgets(2));

    // 7. Row popup menu: Edit & Send opens Send Message pre-filled, and
    // sending it produces a third copy.
    await tester.tap(popupMenuFor(payloadA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit & Send'));
    await tester.pumpAndSettle();
    // Scope to the dialog and pick fields by position (Subject, then Data)
    // rather than by label/hint text — both fields set matching
    // `labelText`/`hintText`, and at this point in the test other on-screen
    // text can coincidentally collide with a `find.widgetWithText` lookup.
    final dialogFields = find.descendant(
        of: find.byType(SendMessageDialog),
        matching: find.byType(TextFormField));
    final subjectField = tester.widget<TextFormField>(dialogFields.at(0));
    final dataField = tester.widget<TextFormField>(dialogFields.at(1));
    expect(subjectField.controller!.text, subjectA);
    expect(dataField.controller!.text, payloadA);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await pumpUntil(
        tester, () => messageRowText(payloadA).evaluate().length >= 3);
    expect(messageRowText(payloadA), findsNWidgets(3));

    // 8. Ctrl+F moves focus to Find; Ctrl+Shift+F moves focus to Filter
    // (per `app_help.md`'s "Global Shortcuts" section and the handler in
    // `lib/main.dart` — note this is the reverse of what the names might
    // suggest). Checked directly via `Focus.of(...).hasFocus` rather than by
    // typing a character afterward and reading a controller: this app's
    // outer `Focus(onKeyEvent: ...)` only sees the key event bubble up from
    // wherever focus currently sits, so start from a known baseline (tap
    // the Filter field itself) rather than whatever had focus after the
    // Edit & Send dialog closed.
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
        reason: 'Ctrl+F should move focus to the Find field');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(fieldHasFocus(Icons.filter_list), isTrue,
        reason: 'Ctrl+Shift+F should move focus to the Filter field');

    // 9. Selecting a message (single tap, debounced 300ms so it isn't read
    // as a double-tap) then pressing D opens its Detail dialog — proving
    // the `selectedIndex` + `Shortcuts`/`Actions` keyboard path works, not
    // just the equivalent popup-menu action already covered above. The
    // Filter field still holds keyboard focus from step 8, and a focused
    // `EditableText` consumes plain character keys as typed input before
    // the app's outer `Focus(onKeyEvent: ...)` ever sees them — explicitly
    // unfocus it first so 'D' actually reaches the shortcut handler instead
    // of being typed into the Filter box.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(messageRowText(payloadB));
    // Wait for a real, verifiable signal that `selectedIndex` actually
    // updated — the row's own selected-state tile color — rather than
    // guessing a fixed delay past the 300ms single/double-tap debounce.
    final rowFinder = rowFor(payloadB);
    final selectedColor =
        Theme.of(tester.element(rowFinder)).colorScheme.inversePrimary;
    await pumpUntil(
        tester,
        () =>
            tester.widget<ListTile>(rowFinder).tileColor == selectedColor,
        timeout: const Duration(seconds: 2));
    // Tapping a ListTile selects it (via its own onTap) but doesn't grant
    // it keyboard focus the way tapping a text field does, so with nothing
    // focused, the key event has no focused node to bubble up from —
    // explicitly request focus so the app's outer `Focus(onKeyEvent: ...)`
    // is back in the dispatch path.
    Focus.of(tester.element(rowFinder)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.text('Message Detail'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
  });
}
