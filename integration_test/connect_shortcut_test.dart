import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;

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
      'Ctrl+Enter in the Subjects field connects while disconnected',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefScheme, constants.defaultScheme);
    await prefs.setString(constants.prefHost, constants.defaultHost);
    await prefs.setString(constants.prefPort, constants.defaultPort);
    await prefs.setString(constants.prefSubject, constants.defaultSubject);
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

    // `.first`: same double-count as the Host field above.
    await tester.tap(find.widgetWithText(TextFormField, 'Subjects').first);
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
