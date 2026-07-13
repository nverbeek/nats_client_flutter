import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/connection_history.dart';
import 'package:nats_client_flutter/constants.dart' as constants;
import 'package:nats_client_flutter/main.dart' as app;

/// Exercises the Host field's connection-history dropdown (Milestone 12 in
/// ROADMAP.md): showing seeded entries, filtering as you type, selecting an
/// entry by mouse or keyboard, and per-entry delete / Clear history. None of
/// this needs a live `nats-server` -- it's pure UI/preferences mechanics --
/// so this seeds prefs directly and boots the app disconnected, mirroring
/// `helpers/nats_test_app.dart`'s `pumpDisconnectedApp` but with an
/// additional `prefConnectionHistory` seed that helper has no parameter for.
/// (*When* an entry gets recorded -- a successful connect, never a failed
/// one -- is covered separately in `record_connection_history_test.dart`,
/// which does need a real server.)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const entryLocal = ConnectionHistoryEntry(
      scheme: 'nats://', host: '127.0.0.1', port: '4222');
  const entryDemo = ConnectionHistoryEntry(
      scheme: 'ws://', host: 'demo.nats.io', port: '8080');

  /// Seeds prefs (connection history plus the same baseline
  /// `pumpDisconnectedApp` uses) and boots the app. The connection bar's own
  /// host/port are deliberately seeded to a value that matches neither
  /// seeded history entry, so "the dropdown shows history" can't be
  /// confused with "the field's own current value happens to match one".
  Future<void> pumpAppWithHistory(
    WidgetTester tester,
    List<ConnectionHistoryEntry> history,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        constants.prefConnectionHistory, encodeConnectionHistory(history));
    await prefs.setString(constants.prefScheme, 'nats://');
    await prefs.setString(constants.prefHost, '192.168.1.50');
    await prefs.setString(constants.prefPort, '9999');
    await prefs.setString(constants.prefSubject, constants.defaultSubject);
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

  // The Host field's hintText and labelText are both "Host" -- `.first`
  // avoids double-counting the same TextFormField, same quirk noted in
  // AGENTS.md Recipe F and already worked around in connect_shortcut_test.dart.
  Finder hostField() => find.widgetWithText(TextFormField, 'Host').first;
  Finder portField() => find.widgetWithText(TextFormField, 'Port').first;

  Finder rowFor(ConnectionHistoryEntry entry) => find.ancestor(
        of: find.text(entry.fullUri),
        matching: find.byType(ListTile),
      );

  Finder deleteButtonFor(ConnectionHistoryEntry entry) => find.descendant(
        of: rowFor(entry),
        matching: find.byIcon(Icons.close),
      );

  testWidgets(
      'tapping the Host field opens a dropdown showing seeded history',
      (tester) async {
    await pumpAppWithHistory(tester, [entryLocal, entryDemo]);

    expect(find.text(entryLocal.fullUri), findsNothing);
    expect(find.text(entryDemo.fullUri), findsNothing);

    await tester.tap(hostField());
    await tester.pump();

    expect(find.text(entryLocal.fullUri), findsOneWidget);
    expect(find.text(entryDemo.fullUri), findsOneWidget);
  });

  testWidgets('an empty history shows no dropdown content on tap',
      (tester) async {
    await pumpAppWithHistory(tester, []);

    await tester.tap(hostField());
    await tester.pump();

    expect(find.text('Clear history'), findsNothing);
  });

  testWidgets('typing filters the dropdown to matching entries',
      (tester) async {
    await pumpAppWithHistory(tester, [entryLocal, entryDemo]);

    await tester.tap(hostField());
    await tester.pump();
    expect(find.text(entryDemo.fullUri), findsOneWidget);

    await tester.enterText(hostField(), '127');
    await tester.pump();

    expect(find.text(entryLocal.fullUri), findsOneWidget);
    expect(find.text(entryDemo.fullUri), findsNothing);
  });

  testWidgets('selecting a history entry by tap fills scheme, host, and port',
      (tester) async {
    await pumpAppWithHistory(tester, [entryDemo]);

    await tester.tap(hostField());
    await tester.pump();
    await tester.tap(find.text(entryDemo.fullUri));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(hostField()).controller!.text,
        entryDemo.host);
    expect(tester.widget<TextFormField>(portField()).controller!.text,
        entryDemo.port);
    expect(find.text(entryDemo.scheme), findsOneWidget);
  });

  testWidgets(
      'ArrowDown then Enter selects the highlighted entry, not just the default first one',
      (tester) async {
    // entryLocal sits at index 0 (front of the seeded list, so it's already
    // highlighted by default); pressing ArrowDown once before Enter moves
    // the highlight to index 1 (entryDemo) -- this specifically exercises
    // keyboard navigation, not just Enter's default-index behavior.
    await pumpAppWithHistory(tester, [entryLocal, entryDemo]);

    await tester.tap(hostField());
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(hostField()).controller!.text,
        entryDemo.host);
    expect(tester.widget<TextFormField>(portField()).controller!.text,
        entryDemo.port);
  });

  testWidgets('deleting one entry removes only that row, dropdown stays open',
      (tester) async {
    await pumpAppWithHistory(tester, [entryLocal, entryDemo]);

    await tester.tap(hostField());
    await tester.pump();
    expect(find.text(entryLocal.fullUri), findsOneWidget);
    expect(find.text(entryDemo.fullUri), findsOneWidget);

    await tester.tap(deleteButtonFor(entryLocal));
    await tester.pump();

    expect(find.text(entryLocal.fullUri), findsNothing);
    expect(find.text(entryDemo.fullUri), findsOneWidget);
    expect(find.text('Clear history'), findsOneWidget);

    // The removal is persisted, not just a local/visual change.
    final prefs = await SharedPreferences.getInstance();
    final persisted = decodeConnectionHistory(
        prefs.getString(constants.prefConnectionHistory)!);
    expect(persisted.any((e) => e.sameTarget(entryLocal)), isFalse);
    expect(persisted.any((e) => e.sameTarget(entryDemo)), isTrue);
  });

  testWidgets('Clear history removes every entry', (tester) async {
    await pumpAppWithHistory(tester, [entryLocal, entryDemo]);

    await tester.tap(hostField());
    await tester.pump();
    await tester.tap(find.text('Clear history'));
    await tester.pump();

    expect(find.text(entryLocal.fullUri), findsNothing);
    expect(find.text(entryDemo.fullUri), findsNothing);
    expect(find.text('Clear history'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    final persisted = decodeConnectionHistory(
        prefs.getString(constants.prefConnectionHistory)!);
    expect(persisted, isEmpty);
  });
}
