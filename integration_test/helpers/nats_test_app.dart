import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;

/// Repeatedly pumps [tester] until [condition] is true, or throws a
/// [TimeoutException] after [timeout]. Real network/connection state
/// changes arrive asynchronously (see `natsConnect()`'s status stream in
/// `lib/main.dart`), so a single `pumpAndSettle()` isn't reliable here —
/// this polls instead.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Pumps for a fixed [duration] without polling for any condition. Use this
/// (instead of `pumpUntil`) when asserting something did *not* happen after
/// a network action -- e.g. no message arrived for a subject that was just
/// unsubscribed -- since there's no positive event to wait for there.
Future<void> pumpBriefly(
  WidgetTester tester, {
  Duration duration = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Seeds `SharedPreferences` with a known-good connection configuration
/// pointing at a local, JetStream-enabled `nats-server` (see
/// `AGENTS.md` "Recipe E: Local JetStream Testing" for how to start one),
/// boots the real app entrypoint (`lib/main.dart`'s `main()`), taps
/// Connect, and waits for the "Connected" status.
///
/// `shared_preferences` on desktop persists to a real file on disk, so
/// without this explicit seeding a prior local run's leftover
/// host/port/subject/TLS settings would silently change what a re-run is
/// actually testing against. Seeding real preference keys (rather than
/// mocking the plugin) keeps this test exercising the exact same
/// preferences code path the real app uses.
Future<void> pumpConnectedApp(
  WidgetTester tester, {
  String subject = constants.defaultSubject,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(constants.prefScheme, constants.defaultScheme);
  await prefs.setString(constants.prefHost, constants.defaultHost);
  await prefs.setString(constants.prefPort, constants.defaultPort);
  await prefs.setString(constants.prefSubject, subject);
  // Startup prefers prefSubscriptions (JSON) over the legacy prefSubject and
  // only migrates from prefSubject when prefSubscriptions is absent -- clear
  // it so a prior test's migrated/edited subscription list on disk doesn't
  // silently override the `subject` param above.
  await prefs.remove(constants.prefSubscriptions);
  await prefs.setBool(constants.prefJetStreamEnabled, true);
  await prefs.setBool(constants.prefKvEnabled, true);
  await prefs.setBool(constants.prefObjectStoreEnabled, true);
  await prefs.setString(constants.prefTrustedCertificate, '');
  await prefs.setString(constants.prefTrustedCertificateName, '');
  await prefs.setString(constants.prefCertificateChain, '');
  await prefs.setString(constants.prefCertificateChainName, '');
  await prefs.setString(constants.prefPrivateKey, '');
  await prefs.setString(constants.prefPrivateKeyName, '');
  await prefs.setBool(constants.prefUpdateCheckEnabled, false);

  app.main();
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.check));
  await pumpUntil(
    tester,
    () => find.text('Status: ${constants.connected}').evaluate().isNotEmpty,
  );
}

/// Same preference seeding as [pumpConnectedApp], but skips tapping Connect
/// — for tests that only need the app's own UI (Settings, tab bar, etc.)
/// and have no reason to require a locally-running `nats-server`.
Future<void> pumpDisconnectedApp(
  WidgetTester tester, {
  String subject = constants.defaultSubject,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(constants.prefScheme, constants.defaultScheme);
  await prefs.setString(constants.prefHost, constants.defaultHost);
  await prefs.setString(constants.prefPort, constants.defaultPort);
  await prefs.setString(constants.prefSubject, subject);
  await prefs.remove(constants.prefSubscriptions);
  await prefs.setBool(constants.prefJetStreamEnabled, true);
  await prefs.setBool(constants.prefKvEnabled, true);
  await prefs.setBool(constants.prefObjectStoreEnabled, true);
  await prefs.setString(constants.prefTrustedCertificate, '');
  await prefs.setString(constants.prefTrustedCertificateName, '');
  await prefs.setString(constants.prefCertificateChain, '');
  await prefs.setString(constants.prefCertificateChainName, '');
  await prefs.setString(constants.prefPrivateKey, '');
  await prefs.setString(constants.prefPrivateKeyName, '');
  await prefs.setBool(constants.prefUpdateCheckEnabled, false);

  app.main();
  await tester.pumpAndSettle();
}

/// Waits for any currently-showing `SnackBar` to finish its auto-dismiss.
///
/// `pumpAndSettle()` only waits while frames are actively being scheduled
/// (e.g. the snackbar's slide-in/fade-in animation) — once that transition
/// finishes it "settles" even though the snackbar stays fully visible for
/// its remaining show duration (Material's default is 4s), pinned to the
/// bottom of the Scaffold. Since this app's bottom toolbar (Send/Filter/
/// Find) sits in that same screen region, a lingering snackbar can
/// silently absorb taps meant for those buttons. Call this after asserting
/// a snackbar's text before interacting with anything near the bottom of
/// the window.
Future<void> waitForSnackBarGone(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  await pumpUntil(
    tester,
    () => find.byType(SnackBar).evaluate().isEmpty,
    timeout: timeout,
  );
}

/// Taps Disconnect and waits for the "Disconnected" status. Intended to be
/// called from a `tearDown` so a failing assertion mid-test doesn't leak a
/// live connection into the next test.
Future<void> disconnectApp(WidgetTester tester) async {
  final disconnectButton = find.widgetWithIcon(ElevatedButton, Icons.close);
  if (disconnectButton.evaluate().isEmpty) return;

  await tester.tap(disconnectButton);
  await pumpUntil(
    tester,
    () =>
        find.text('Status: ${constants.disconnected}').evaluate().isNotEmpty,
  );
}
