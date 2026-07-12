import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;
import 'package:nats_client_flutter/subject_chips_row.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the Ctrl+Enter (Cmd+Enter on Mac) shortcut that fires Connect
/// while focus is in the Host/Port/Subjects fields and the client isn't
/// already connected, against a real, locally-running `nats-server` (see
/// AGENTS.md "Recipe E: Local JetStream Testing"). Deliberately does not
/// use `pumpConnectedApp` (which connects via tapping the checkmark
/// button) — this test needs the app to start disconnected so it can
/// connect via the shortcut instead.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Ctrl+Enter in the Host field connects while disconnected',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefScheme, constants.defaultScheme);
    await prefs.setString(constants.prefHost, constants.defaultHost);
    await prefs.setString(constants.prefPort, constants.defaultPort);
    await prefs.setString(constants.prefSubject, constants.defaultSubject);
    // Startup prefers prefSubscriptions (JSON) over the legacy prefSubject
    // and only migrates from prefSubject when prefSubscriptions is absent --
    // clear it so a prior run's persisted subscription list on disk doesn't
    // silently override defaultSubject above.
    await prefs.remove(constants.prefSubscriptions);
    await prefs.setBool(constants.prefJetStreamEnabled, true);
    await prefs.setString(constants.prefTrustedCertificate, '');
    await prefs.setString(constants.prefTrustedCertificateName, '');
    await prefs.setString(constants.prefCertificateChain, '');
    await prefs.setString(constants.prefCertificateChainName, '');
    await prefs.setString(constants.prefPrivateKey, '');
    await prefs.setString(constants.prefPrivateKeyName, '');
    await prefs.setBool(constants.prefUpdateCheckEnabled, false);

    app.main();
    await tester.pumpAndSettle();
    addTearDown(() => disconnectApp(tester));

    expect(find.text('Status: ${constants.disconnected}'), findsOneWidget);

    // `.first`: the Host field's hintText and labelText are both "Host",
    // so `find.widgetWithText` double-counts the same TextFormField (see
    // the same quirk noted in AGENTS.md Recipe F re: find.text/RichText).
    await tester.tap(find.widgetWithText(TextFormField, 'Host').first);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

    await pumpUntil(
      tester,
      () => find.text('Status: ${constants.connected}').evaluate().isNotEmpty,
    );
  });

  testWidgets(
      'Ctrl+Enter in the Subjects chip row connects while disconnected',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefScheme, constants.defaultScheme);
    await prefs.setString(constants.prefHost, constants.defaultHost);
    await prefs.setString(constants.prefPort, constants.defaultPort);
    await prefs.setString(constants.prefSubject, constants.defaultSubject);
    // Startup prefers prefSubscriptions (JSON) over the legacy prefSubject
    // and only migrates from prefSubject when prefSubscriptions is absent --
    // clear it so a prior run's persisted subscription list on disk doesn't
    // silently override defaultSubject above.
    await prefs.remove(constants.prefSubscriptions);
    await prefs.setBool(constants.prefJetStreamEnabled, true);
    await prefs.setString(constants.prefTrustedCertificate, '');
    await prefs.setString(constants.prefTrustedCertificateName, '');
    await prefs.setString(constants.prefCertificateChain, '');
    await prefs.setString(constants.prefCertificateChainName, '');
    await prefs.setString(constants.prefPrivateKey, '');
    await prefs.setString(constants.prefPrivateKeyName, '');
    await prefs.setBool(constants.prefUpdateCheckEnabled, false);

    app.main();
    await tester.pumpAndSettle();
    addTearDown(() => disconnectApp(tester));

    // The Subjects field is now a SubjectChipsRow. Tap near its right edge
    // rather than its geometric center or a specific chip/button: like a
    // real TextFormField, tapping empty space within the field just focuses
    // it (see the row's own GestureDetector) without triggering an action --
    // tapping the "+" button instead would open the Add Subscription dialog,
    // which sits outside the toolbar's Shortcuts/Actions ancestry and would
    // swallow the Ctrl+Enter keystroke. The row's content (label + chips +
    // "+") is left-aligned and only ever occupies part of its width, so the
    // trailing edge is reliably blank regardless of how many/how long the
    // subscriptions are -- unlike the row's center, which a single long
    // subject's chip can end up covering.
    final chipsRowRect = tester.getRect(find.byType(SubjectChipsRow));
    await tester.tapAt(
        Offset(chipsRowRect.right - 8, chipsRowRect.center.dy));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

    await pumpUntil(
      tester,
      () => find.text('Status: ${constants.connected}').evaluate().isNotEmpty,
    );
  });
}
