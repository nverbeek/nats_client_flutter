import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';
import 'package:nats_client_flutter/send_message_dialog.dart';

import 'helpers/nats_test_app.dart';

/// Verifies headers attached in `SendMessageDialog` actually reach the wire
/// and round-trip back through a real, locally-running `nats-server` (see
/// AGENTS.md "Recipe E: Local JetStream Testing" for how to start one —
/// this test only needs plain NATS, no `-js` flag required).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a header attached in Send Message appears in the received message detail',
      (tester) async {
    // Default subscribed subject is '>' (see constants.defaultSubject), so
    // the app receives its own publish — a full publish -> subscribe -> UI
    // round trip through the real server.
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final uniqueSubject =
        'integration.headers.${DateTime.now().microsecondsSinceEpoch}';
    final uniquePayload =
        'integration-header-payload-${DateTime.now().microsecondsSinceEpoch}';
    const headerKey = 'X-Trace-Id';
    final headerValue = 'trace-${DateTime.now().microsecondsSinceEpoch}';

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'), uniqueSubject);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Data'), uniquePayload);

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();

    // `find.byType(TextFormField).at(n)` is not scoped to the open dialog —
    // it matches every mounted TextFormField app-wide, including the
    // (disabled but still mounted) Host/Port/Subjects connection-bar
    // fields, so index positions must be scoped to the dialog itself. See
    // the identical gotcha noted for KV dialog tests.
    final dialogFields = find.descendant(
        of: find.byType(SendMessageDialog),
        matching: find.byType(TextFormField));
    // Field order within the dialog is subject, data, header key, header
    // value (see send_message_dialog_test.dart for the same convention).
    await tester.enterText(dialogFields.at(2), headerKey);
    await tester.enterText(dialogFields.at(3), headerValue);

    await tester.tap(find.widgetWithText(TextButton, 'Send'));

    // Matches the custom `RegexTextHighlight` widget the message list uses
    // for row content, deliberately not `find.text()`, which also matches
    // `EditableText` (a Send Message dialog field can transiently hold the
    // same string as a payload already in the list) — see the identical
    // helper in live_messages_interactions_test.dart.
    Finder messageRowText(String payload) => find.byWidgetPredicate(
        (widget) => widget is RegexTextHighlight && widget.text == payload);

    await pumpUntil(
      tester,
      () => messageRowText(uniquePayload).evaluate().isNotEmpty,
    );

    final row = find.ancestor(
        of: messageRowText(uniquePayload), matching: find.byType(ListTile));
    final popupMenu = find.descendant(
        of: row.first, matching: find.byType(PopupMenuButton<String>));

    await tester.tap(popupMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();

    // Headers now render as a two-column table (see message_detail_dialog.dart),
    // with the key and value as separate SelectableText widgets rather than a
    // single combined "key: value" string.
    expect(find.text(headerKey), findsOneWidget);
    expect(find.text(headerValue), findsOneWidget);
  });
}
