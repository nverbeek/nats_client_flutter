import 'package:dart_nats/dart_nats.dart' hide Consumer;
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
}
