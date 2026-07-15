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

  testWidgets('Filter, Find, row menu actions, and keyboard shortcuts all work',
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
    await pumpUntil(tester,
        () => tester.widget<ListTile>(rowFinder).tileColor == selectedColor,
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

  testWidgets(
      'Multi-select (Shift+Click, Ctrl+Shift+Up/Down) and bulk clipboard copy',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subjectA = 'it.multiselect.a.$runId';
    final subjectB = 'it.multiselect.b.$runId';
    final subjectC = 'it.multiselect.c.$runId';
    final subjectD = 'it.multiselect.d.$runId';
    final payloadA = 'it-multiselect-payload-a-$runId';
    final payloadB = 'it-multiselect-payload-b-$runId';
    final payloadC = 'it-multiselect-payload-c-$runId';
    // Embedded real newline -- exercises the "escaped as literal \n so line
    // count always equals message count" rule.
    final payloadD = 'it-multiselect-payload-d-$runId-line1\nline2';

    Future<void> sendCoreMessage(String subject, String data) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), subject);
      await tester.enterText(find.widgetWithText(TextFormField, 'Data'), data);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntil(tester, () => find.text(data).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
    }

    Finder rowFor(String payload) => find.ancestor(
        of: messageRowText(payload), matching: find.byType(ListTile));
    Finder popupMenuFor(String payload) => find.descendant(
        of: rowFor(payload).first,
        matching: find.byType(PopupMenuButton<String>));

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

    // Sent in this order, so newest-first on-screen top-to-bottom order is:
    // D, C, B, A.
    await sendCoreMessage(subjectA, payloadA);
    await sendCoreMessage(subjectB, payloadB);
    await sendCoreMessage(subjectC, payloadC);
    await sendCoreMessage(subjectD, payloadD);
    expect(messageRowText(payloadA), findsOneWidget);
    expect(messageRowText(payloadB), findsOneWidget);
    expect(messageRowText(payloadC), findsOneWidget);
    expect(messageRowText(payloadD), findsOneWidget);

    final selectedColor =
        Theme.of(tester.element(rowFor(payloadA))).colorScheme.inversePrimary;
    bool isSelected(String payload) =>
        tester.widget<ListTile>(rowFor(payload)).tileColor == selectedColor;

    // 1. Shift+Click range select: plain-click C (sets the anchor), then
    // Shift+Click D (adjacent, at the top) to select {C, D}. Also verifies
    // embedded-newline escaping in the resulting Ctrl+C output.
    await tester.tap(messageRowText(payloadC));
    await pumpUntil(tester, () => isSelected(payloadC),
        timeout: const Duration(seconds: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(messageRowText(payloadD));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(isSelected(payloadC), isTrue);
    expect(isSelected(payloadD), isTrue);
    expect(isSelected(payloadA), isFalse);
    expect(isSelected(payloadB), isFalse);

    Focus.of(tester.element(rowFor(payloadD))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    final escapedPayloadD = payloadD.replaceAll('\n', r'\n');
    final expectedNewlineText =
        '$subjectD: $escapedPayloadD\n$subjectC: $payloadC';
    expect(copiedData, contains(expectedNewlineText));
    expect(expectedNewlineText.split('\n'), hasLength(2),
        reason: 'copied line count must equal selected message count even '
            "though one payload's own embedded newline was escaped");
    expect(find.text('Copied 2 messages to clipboard!'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 2. Shift+Click a wider range: plain-click A (new anchor), then
    // Shift+Click C -- selects {A, B, C} (D excluded).
    await tester.tap(messageRowText(payloadA));
    await pumpUntil(tester, () => isSelected(payloadA),
        timeout: const Duration(seconds: 2));
    expect(isSelected(payloadB), isFalse);
    expect(isSelected(payloadC), isFalse);
    expect(isSelected(payloadD), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(messageRowText(payloadC));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(isSelected(payloadA), isTrue,
        reason: 'range should include the original anchor row');
    expect(isSelected(payloadB), isTrue,
        reason: 'range should include rows between anchor and target');
    expect(isSelected(payloadC), isTrue,
        reason: 'range should include the clicked row');
    expect(isSelected(payloadD), isFalse);

    // 3. Ctrl+Shift+Down shrinks the range by one row, moving the focus
    // edge from C (top of the range) toward the fixed anchor at A.
    Focus.of(tester.element(rowFor(payloadC))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(isSelected(payloadC), isFalse,
        reason: 'Ctrl+Shift+Down should shrink the range away from C');
    expect(isSelected(payloadB), isTrue);
    expect(isSelected(payloadA), isTrue);

    // Ctrl+Shift+Up grows the range back to include C.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(isSelected(payloadC), isTrue,
        reason: 'Ctrl+Shift+Up should grow the range back to include C');
    expect(isSelected(payloadB), isTrue);
    expect(isSelected(payloadA), isTrue);

    // 4. Ctrl+C with 3 rows selected copies "subject: payload" one per
    // line, in on-screen top-to-bottom order (newest first: C, B, A).
    copiedData.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    final expectedMulti =
        '$subjectC: $payloadC\n$subjectB: $payloadB\n$subjectA: $payloadA';
    expect(copiedData, contains(expectedMulti));
    expect(find.text('Copied 3 messages to clipboard!'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 5. "Copy Selected (N)" menu item: opening the row menu on D, which is
    // NOT part of the current {A, B, C} selection, does not fold D in --
    // the bulk action still only copies the existing selection.
    copiedData.clear();
    await tester.tap(popupMenuFor(payloadD));
    await tester.pumpAndSettle();
    expect(find.text('Copy Selected (3)'), findsOneWidget);
    await tester.tap(find.text('Copy Selected (3)'));
    await tester.pumpAndSettle();
    expect(copiedData, contains(expectedMulti));
    expect(find.text('Copied 3 messages to clipboard!'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 6. Ctrl+C with exactly one row selected still copies the bare
    // payload, no subject prefix -- unchanged from today's existing
    // single-select behavior. A plain click collapses the multi-selection.
    // A is already part of the current {A, B, C} selection, so waiting on
    // `isSelected(payloadA)` wouldn't prove anything (it's already true) --
    // wait on B actually flipping to deselected instead, which only happens
    // once the single/double-tap debounce timer fires and clears
    // `_multiSelected`.
    copiedData.clear();
    await tester.tap(messageRowText(payloadA));
    await pumpUntil(tester, () => !isSelected(payloadB),
        timeout: const Duration(seconds: 2));
    expect(isSelected(payloadA), isTrue);
    expect(isSelected(payloadC), isFalse);
    Focus.of(tester.element(rowFor(payloadA))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(copiedData, contains(payloadA));
    expect(copiedData.any((t) => t.contains('$subjectA:')), isFalse);
    expect(find.text('Copied to clipboard!'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // "Copy Selected" is absent from the row menu once only one row is
    // selected.
    await tester.tap(popupMenuFor(payloadA));
    await tester.pumpAndSettle();
    expect(find.textContaining('Copy Selected'), findsNothing);
    await tester.tap(find.text('Detail')); // dismiss the menu via a real item
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // 7. Selection survives a new message arriving mid-selection: re-select
    // A+B as a range, send a brand-new message (prepended above them via
    // `_insertMessages`), and confirm both rows are still shown selected --
    // proving the identity-based Set survives the prepend with no index
    // shifting needed. Anchor on B (currently unselected) rather than
    // re-clicking A -- A is still the sole `selectedIndex` from the
    // previous step, and a plain click on the row that's already
    // `selectedIndex` toggles it OFF rather than re-selecting it.
    await tester.tap(messageRowText(payloadB));
    await pumpUntil(tester, () => isSelected(payloadB),
        timeout: const Duration(seconds: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(messageRowText(payloadA));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(isSelected(payloadA), isTrue);
    expect(isSelected(payloadB), isTrue);

    final subjectE = 'it.multiselect.e.$runId';
    final payloadE = 'it-multiselect-payload-e-$runId';
    await sendCoreMessage(subjectE, payloadE);
    expect(isSelected(payloadA), isTrue,
        reason: 'identity-based selection should survive a new message '
            'prepending above the selected rows');
    expect(isSelected(payloadB), isTrue);

    // 8. Selection survives a Filter-field change that still matches the
    // selected rows (filteredItems is reassigned wholesale by _runFilter).
    await tester.enterText(fieldWithPrefixIcon(Icons.filter_list), '$runId');
    await tester.pump();
    expect(isSelected(payloadA), isTrue,
        reason: 'selection should survive filteredItems being reassigned');
    expect(isSelected(payloadB), isTrue);
    await tester.tap(find.descendant(
        of: fieldWithPrefixIcon(Icons.filter_list),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();
  });

  testWidgets(
      'Ctrl+C reclaims focus from the Filter field, and CRLF payloads '
      'collapse to one line each', (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subjectA = 'it.multiselect2.a.$runId';
    final subjectB = 'it.multiselect2.b.$runId';
    // Real-world payloads built from concatenated CRLF-terminated lines
    // (e.g. NMEA sentences) -- replacing only bare `\n` would leave the `\r`
    // behind, which still renders as a line break wherever it's pasted.
    final payloadA = 'it-multiselect2-payload-a-$runId-line1\r\nline2';
    final payloadB = 'it-multiselect2-payload-b-$runId';

    Future<void> sendCoreMessage(String subject, String data) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), subject);
      await tester.enterText(find.widgetWithText(TextFormField, 'Data'), data);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntil(tester, () => find.text(data).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
    }

    Finder rowFor(String payload) => find.ancestor(
        of: messageRowText(payload), matching: find.byType(ListTile));

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

    await sendCoreMessage(subjectA, payloadA);
    await sendCoreMessage(subjectB, payloadB);
    expect(messageRowText(payloadA), findsOneWidget);
    expect(messageRowText(payloadB), findsOneWidget);

    // Deliberately give the Filter field focus first and never explicitly
    // request focus back onto the message list -- this reproduces a real
    // user's workflow (type a filter, then select some rows) rather than
    // relying on this test file's usual `Focus.of(...).requestFocus()`
    // workaround, which would mask a regression in the app's own focus
    // handling.
    await tester.tap(fieldWithPrefixIcon(Icons.filter_list));
    await tester.pump();
    expect(
        Focus.of(tester.element(fieldWithPrefixIcon(Icons.filter_list)))
            .hasFocus,
        isTrue);

    await tester.tap(messageRowText(payloadA));
    final rowFinder = rowFor(payloadA);
    final selectedColor =
        Theme.of(tester.element(rowFinder)).colorScheme.inversePrimary;
    await pumpUntil(tester,
        () => tester.widget<ListTile>(rowFinder).tileColor == selectedColor,
        timeout: const Duration(seconds: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(messageRowText(payloadB));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    final expected =
        '$subjectB: $payloadB\n$subjectA: ${payloadA.replaceAll('\r\n', r'\n')}';
    expect(copiedData, contains(expected));
    expect(expected.split('\n'), hasLength(2),
        reason: 'a CRLF-separated payload must still collapse to exactly '
            'one copied line');
    expect(expected.contains('\r'), isFalse,
        reason: 'no raw carriage return should survive into the copied text');
    expect(find.text('Copied 2 messages to clipboard!'), findsOneWidget);
  });

  testWidgets(
      'Ctrl+Click toggles individual rows into/out of a disconnected '
      'selection', (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final subjectA = 'it.ctrlclick.a.$runId';
    final subjectB = 'it.ctrlclick.b.$runId';
    final subjectC = 'it.ctrlclick.c.$runId';
    final subjectD = 'it.ctrlclick.d.$runId';
    final payloadA = 'it-ctrlclick-payload-a-$runId';
    final payloadB = 'it-ctrlclick-payload-b-$runId';
    final payloadC = 'it-ctrlclick-payload-c-$runId';
    final payloadD = 'it-ctrlclick-payload-d-$runId';

    Future<void> sendCoreMessage(String subject, String data) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), subject);
      await tester.enterText(find.widgetWithText(TextFormField, 'Data'), data);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await pumpUntil(tester, () => find.text(data).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
    }

    Finder rowFor(String payload) => find.ancestor(
        of: messageRowText(payload), matching: find.byType(ListTile));

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

    // Sent in this order, so newest-first on-screen top-to-bottom order is:
    // D, C, B, A.
    await sendCoreMessage(subjectA, payloadA);
    await sendCoreMessage(subjectB, payloadB);
    await sendCoreMessage(subjectC, payloadC);
    await sendCoreMessage(subjectD, payloadD);

    final selectedColor =
        Theme.of(tester.element(rowFor(payloadA))).colorScheme.inversePrimary;
    bool isSelected(String payload) =>
        tester.widget<ListTile>(rowFor(payload)).tileColor == selectedColor;

    Future<void> ctrlTap(Finder finder) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.tap(finder);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
    }

    // 1. Ctrl+Click with nothing selected just selects that one row. The
    // status bar's "Selected: N" count only appears once something is
    // selected.
    expect(find.textContaining('Selected:'), findsNothing);
    await ctrlTap(messageRowText(payloadA));
    expect(isSelected(payloadA), isTrue);
    expect(isSelected(payloadB), isFalse);
    expect(isSelected(payloadC), isFalse);
    expect(find.textContaining('Selected: 1'), findsOneWidget);

    // 2. Ctrl+Click a non-adjacent row adds it without selecting the rows
    // in between -- a genuinely disconnected selection (B stays
    // unselected even though it sits between A and C on screen).
    await ctrlTap(messageRowText(payloadC));
    expect(isSelected(payloadA), isTrue);
    expect(isSelected(payloadB), isFalse,
        reason: 'Ctrl+Click must not select rows between the two clicks');
    expect(isSelected(payloadC), isTrue);
    expect(isSelected(payloadD), isFalse);
    expect(find.textContaining('Selected: 2'), findsOneWidget);

    // Ctrl+C copies exactly the two selected (non-adjacent) rows, in
    // on-screen order -- relies on the earlier focus fix (clicking a row
    // reclaims keyboard focus), not an explicit test-only workaround.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(copiedData, contains('$subjectC: $payloadC\n$subjectA: $payloadA'));
    expect(find.text('Copied 2 messages to clipboard!'), findsOneWidget);
    await waitForSnackBarGone(tester);

    // 3. Ctrl+Click an already-selected row removes just that row.
    await ctrlTap(messageRowText(payloadA));
    expect(isSelected(payloadA), isFalse);
    expect(isSelected(payloadC), isTrue);
    expect(find.textContaining('Selected: 1'), findsOneWidget);

    // 4. Ctrl+Click the last remaining selected row deselects it too,
    // leaving nothing selected -- rather than crashing, or falling back to
    // showing some other row (e.g. the last-clicked one) as selected. The
    // status bar's "Selected: N" disappears again once nothing is selected.
    await ctrlTap(messageRowText(payloadC));
    expect(isSelected(payloadC), isFalse);
    expect(isSelected(payloadA), isFalse);
    expect(isSelected(payloadB), isFalse);
    expect(isSelected(payloadD), isFalse);
    expect(find.textContaining('Selected:'), findsNothing);

    // Ctrl+C with nothing selected is a safe no-op: doesn't throw, and
    // doesn't copy stale data from a previous selection.
    copiedData.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(copiedData, isEmpty);

    // 5. Ctrl+Click also moves the anchor for a later Shift+Click: select D
    // via Ctrl+Click, then Shift+Click B -- the resulting range should run
    // from D down to B (D, C, B), anchored at the Ctrl+Click, not at
    // whatever an earlier gesture had set.
    await ctrlTap(messageRowText(payloadD));
    expect(isSelected(payloadD), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(messageRowText(payloadB));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(isSelected(payloadD), isTrue);
    expect(isSelected(payloadC), isTrue);
    expect(isSelected(payloadB), isTrue);
    expect(isSelected(payloadA), isFalse);
  });
}
