import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;

import 'helpers/nats_test_app.dart';

/// Exercises the four Milestone 4 (Phase D) authentication methods against
/// real, purpose-built `nats-server` containers — one per method, since
/// NATS's simple `authorization` block (user/pass, token, bare nkey) and its
/// operator/JWT mode are mutually exclusive server configs. See
/// `integration_test/fixtures/auth/` for each server's config (and
/// `test-user.creds` for the `.creds` case) and AGENTS.md's auth recipe for
/// how to run them locally.
///
/// Only the "correct credentials connect successfully" path is covered here.
/// The "wrong credentials surface the friendly error" path is deliberately
/// not automated: a real `dart_nats` quirk (an internal `Completer` that's
/// never awaited on this app's `retryCount: -1` connect path gets
/// `completeError()`'d when the server sends `-ERR Authorization Violation`)
/// makes `flutter test`'s stricter zone treat that as a fatal test failure
/// even though the app itself handles it correctly — confirmed with a
/// standalone `runZonedGuarded` probe, not chased further here since fixing
/// it would mean changing this app's global reconnect semantics.
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
}
