import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/connection_history.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;

import 'helpers/nats_test_app.dart';

/// Verifies *when* a connection is recorded into history against a real
/// `nats-server` (see AGENTS.md "Recipe D: Local Mock Testing" -- a plain
/// `docker run -d -p 4222:4222 nats` is enough here; JetStream isn't
/// needed): only on a successful `Status.connected`, never on a failed
/// attempt. Dropdown display/filter/select/delete mechanics are covered
/// without a server in `connection_history_test.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seedBaseline(
      {required String host, required String port}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(constants.prefScheme, constants.defaultScheme);
    await prefs.setString(constants.prefHost, host);
    await prefs.setString(constants.prefPort, port);
    await prefs.remove(constants.prefConnectionHistory);
    await prefs.setString(constants.prefSubject, constants.defaultSubject);
    await prefs.remove(constants.prefSubscriptions);
    await prefs.setBool(constants.prefJetStreamEnabled, false);
    await prefs.setBool(constants.prefKvEnabled, false);
    await prefs.setBool(constants.prefObjectStoreEnabled, false);
    // Deliberately not touching prefRetryInterval: a connection-refused
    // failure surfaces on the *first* attempt regardless of the interval
    // between retries, so the default is fine -- and shared_preferences
    // persists to a real file on this desktop target, so seeding a value
    // outside the Settings dialog's valid dropdown options (3/5/10/30)
    // here would silently corrupt any *other* test run afterward that
    // opens Settings without re-seeding it (this bit settings_tab_toggle_
    // test.dart once already; don't reintroduce it).
    await prefs.setString(constants.prefTrustedCertificate, '');
    await prefs.setString(constants.prefTrustedCertificateName, '');
    await prefs.setString(constants.prefCertificateChain, '');
    await prefs.setString(constants.prefCertificateChainName, '');
    await prefs.setString(constants.prefPrivateKey, '');
    await prefs.setString(constants.prefPrivateKeyName, '');
    await prefs.setBool(constants.prefUpdateCheckEnabled, false);
  }

  Future<List<ConnectionHistoryEntry>> readPersistedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(constants.prefConnectionHistory);
    return (json == null || json.isEmpty)
        ? const []
        : decodeConnectionHistory(json);
  }

  testWidgets('a successful connect records the target into history',
      (tester) async {
    await seedBaseline(host: constants.defaultHost, port: constants.defaultPort);

    app.main();
    await tester.pumpAndSettle();
    addTearDown(() => disconnectApp(tester));

    expect(await readPersistedHistory(), isEmpty);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await pumpUntil(
      tester,
      () => find.text('Status: ${constants.connected}').evaluate().isNotEmpty,
    );

    final history = await readPersistedHistory();
    expect(
      history.any((e) =>
          e.scheme == constants.defaultScheme &&
          e.host == constants.defaultHost &&
          e.port == constants.defaultPort),
      isTrue,
      reason: 'the just-connected target should be recorded',
    );
  });

  testWidgets('a failed connect does not record anything into history',
      (tester) async {
    // Port 1 is not a NATS server -- the connection attempt fails fast
    // (connection refused) without ever reaching Status.connected.
    await seedBaseline(host: constants.defaultHost, port: '1');

    app.main();
    await tester.pumpAndSettle();
    addTearDown(() => disconnectApp(tester));

    expect(await readPersistedHistory(), isEmpty);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await pumpBriefly(tester, duration: const Duration(seconds: 3));

    expect(find.text('Status: ${constants.connected}'), findsNothing);
    expect(await readPersistedHistory(), isEmpty);
  });
}
