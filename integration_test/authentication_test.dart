import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;
import 'package:nats_client_flutter/subscription_info.dart';

import 'helpers/nats_test_app.dart';

/// Exercises the four Milestone 4 (Phase D) authentication methods against
/// real, purpose-built `nats-server` containers — one per method, since
/// NATS's simple `authorization` block (user/pass, token, bare nkey) and its
/// operator/JWT mode are mutually exclusive server configs. See
/// `integration_test/fixtures/auth/` for each server's config (and
/// `test-user.creds` for the `.creds` case) and AGENTS.md's auth recipe for
/// how to run them locally.
///
/// Covers both the "correct credentials connect successfully" path and the
/// "wrong credentials surface the friendly error" path. The latter used to be
/// untestable: before dart_nats 1.5.0, `connect()` resolved as soon as the
/// socket opened, so the server's later `-ERR Authorization Violation`
/// failed an internal `Completer` nobody awaited, which `flutter test`'s
/// zone treats as fatal. `connect()` now waits for the handshake and
/// rethrows the auth failure itself.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seedCommonPrefs(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefScheme, 'nats://');
    await prefs.setString(constants.prefHost, '127.0.0.1');
    await prefs.setString(constants.prefPort, '$port');
    await prefs.setString(constants.prefSubject, constants.defaultSubject);
    await prefs.setBool(constants.prefJetStreamEnabled, false);
    await prefs.setString(constants.prefTrustedCertificate, '');
    await prefs.setString(constants.prefCertificateChain, '');
    await prefs.setString(constants.prefPrivateKey, '');
    await prefs.setBool(constants.prefRememberCredentials, true);
    await prefs.setBool(constants.prefUpdateCheckEnabled, false);
  }

  Future<void> connectAndVerify(WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await pumpUntil(
      tester,
      () => find.text('Status: ${constants.connected}').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
    );

    expect(find.text('Status: ${constants.connected}'), findsOneWidget);
    await disconnectApp(tester);
  }

  testWidgets('username/password connects to its fixture server',
      (tester) async {
    await seedCommonPrefs(4300);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefAuthMethod, 'usernamePassword');
    await prefs.setString(constants.prefAuthUsername, 'integration-test-user');
    await prefs.setString(constants.prefAuthPassword, 'integration-test-pass');

    await connectAndVerify(tester);
  });

  testWidgets('token connects to its fixture server', (tester) async {
    await seedCommonPrefs(4301);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefAuthMethod, 'token');
    await prefs.setString(constants.prefAuthToken, 'integration-test-token');

    await connectAndVerify(tester);
  });

  testWidgets('NKey seed connects to its fixture server', (tester) async {
    await seedCommonPrefs(4302);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefAuthMethod, 'nkeySeed');
    await prefs.setString(constants.prefAuthNkeySeed,
        'SUAN72GFFNFVMKDW5GG4JY6LSRCH6BRGSPCS624MMITENFHOXMXYELOZI4');

    await connectAndVerify(tester);
  });

  testWidgets('credentials file connects to its fixture server',
      (tester) async {
    await seedCommonPrefs(4303);
    final credsBytes = File('integration_test/fixtures/auth/test-user.creds')
        .readAsBytesSync();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefAuthMethod, 'credentialsFile');
    await prefs.setString(
        constants.prefAuthCredsFile, base64.encode(gzip.encode(credsBytes)));
    await prefs.setString(constants.prefAuthCredsFileName, 'test-user.creds');

    await connectAndVerify(tester);
  });

  testWidgets(
      'a wrong password shows the authentication error and stops retrying',
      (tester) async {
    await seedCommonPrefs(4300);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefAuthMethod, 'usernamePassword');
    await prefs.setString(constants.prefAuthUsername, 'integration-test-user');
    await prefs.setString(constants.prefAuthPassword, 'wrong-password');

    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await pumpUntil(
      tester,
      () => find.text(constants.authenticationFailure).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
    );

    // The auth message must not be replaced by the generic connect-failure
    // one, and the client must not keep retrying: it stays Disconnected.
    await pumpBriefly(tester);
    expect(find.text(constants.authenticationFailure), findsOneWidget);
    expect(find.textContaining('${constants.connectionFailureGenericPrefix}: '),
        findsNothing);
    expect(find.text('Status: ${constants.disconnected}'), findsOneWidget);

    await waitForSnackBarGone(tester);
  });

  testWidgets(
      'a subscribe and a publish the server refuses show permission denied '
      'and flag the subscription chip', (tester) async {
    await seedCommonPrefs(4300);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefAuthMethod, 'usernamePassword');
    await prefs.setString(
        constants.prefAuthUsername, 'integration-test-restricted');
    await prefs.setString(constants.prefAuthPassword, 'integration-test-pass');
    await prefs.setString(
        constants.prefSubscriptions,
        encodeSubscriptionList([
          SubscriptionInfo(subject: 'allowed.subject', colorIndex: 0),
          SubscriptionInfo(subject: 'forbidden.subject', colorIndex: 1),
        ]));

    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    final subscribeDenied = constants.permissionDenied(
        publish: false, subject: 'forbidden.subject');
    await pumpUntil(
      tester,
      () => find.text(subscribeDenied).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
    );

    // The connection stays up; only the refused subscription is flagged.
    expect(find.text('Status: ${constants.connected}'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(InputChip), matching: find.byIcon(Icons.block)),
        findsOneWidget);
    await waitForSnackBarGone(tester);

    // MyHomePage has no fake-injection point for the client, so publish
    // through the real one directly (see AGENTS.md Recipe F).
    final state = tester.state(find.byType(app.MyHomePage)) as dynamic;
    await state.natsClient.pubString('forbidden.subject', 'nope');
    final publishDenied =
        constants.permissionDenied(publish: true, subject: 'forbidden.subject');
    await pumpUntil(
      tester,
      () => find.text(publishDenied).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('Status: ${constants.connected}'), findsOneWidget);

    await waitForSnackBarGone(tester);
    await disconnectApp(tester);
  });
}
