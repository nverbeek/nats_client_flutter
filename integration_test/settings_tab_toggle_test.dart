import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Regression test for a crash where turning "Enable JetStream" and/or
/// "Enable Key-Value Stores" off then back on in Settings would leave the
/// app in a broken state ("A TabController was used after being disposed",
/// then a null-check crash inside `TabBar`).
///
/// Root cause: `_MyHomePageState` (`lib/main.dart`) rebuilds its
/// `TabController` at a new length whenever the visible tab count changes
/// (`_ensureTabController()`), which means disposing one `TabController`
/// and constructing another over the State's lifetime — more than once.
/// `SingleTickerProviderStateMixin` only supports vending a single ticker
/// for the *entire lifetime of the State*, even if the first one was
/// properly disposed (see its doc comment); the second `TabController(...)`
/// construction hits `SingleTickerProviderStateMixin.createTicker()`'s
/// "at most one ticker" assertion mid-construction, which leaves
/// `_tabController` pointing at an already-disposed instance from the
/// failed reassignment — everything downstream cascades from there. Fixed
/// by switching to `TickerProviderStateMixin`, which explicitly supports
/// creating and disposing any number of tickers over a State's lifetime.
///
/// Object Store (Milestone 7) added a fourth toggleable tab following the
/// exact same pattern as JetStream/Key-Value, so it's exercised here too.
///
/// No live NATS server is needed — Settings and the tab bar work whether
/// or not the app is connected, so this uses `pumpDisconnectedApp` rather
/// than spinning up `nats-server`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
  }

  Future<void> saveSettings(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'turning JetStream, Key-Value, and Object Store off then back on does not crash the tab bar',
      (tester) async {
    await pumpDisconnectedApp(tester);

    // Starts with all three enabled (seeded prefs): four tabs.
    expect(find.text('Live Messages'), findsOneWidget);
    expect(find.text('JetStream'), findsOneWidget);
    expect(find.text('Key-Value Stores'), findsOneWidget);
    expect(find.text('Object Store'), findsOneWidget);

    // Turn all three off and save.
    await openSettings(tester);
    // Switches, in order: Show Subscription Colors, Enable JetStream, Enable
    // Key-Value Stores, Enable Object Store, Check for Updates.
    await tester.tap(find.byType(Switch).at(1));
    await tester.tap(find.byType(Switch).at(2));
    await tester.tap(find.byType(Switch).at(3));
    await saveSettings(tester);
    expect(tester.takeException(), isNull);

    // Only Live Messages remains. With a single tab there's no `TabBar` at
    // all (see `_visibleTabCount > 1` in `lib/main.dart`), so there's no
    // "Live Messages" *text* anywhere (that string only exists as a `Tab`
    // label) — assert on the status bar, which is always present, instead.
    expect(find.textContaining('Total Messages:'), findsOneWidget);
    expect(find.text('JetStream'), findsNothing);
    expect(find.text('Key-Value Stores'), findsNothing);
    expect(find.text('Object Store'), findsNothing);

    // Turn all three back on and save — this is the step that used to crash.
    await openSettings(tester);
    await tester.tap(find.byType(Switch).at(1));
    await tester.tap(find.byType(Switch).at(2));
    await tester.tap(find.byType(Switch).at(3));
    await saveSettings(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('Live Messages'), findsOneWidget);
    expect(find.text('JetStream'), findsOneWidget);
    expect(find.text('Key-Value Stores'), findsOneWidget);
    expect(find.text('Object Store'), findsOneWidget);

    // The tab bar must still be interactive (this is what actually
    // exercised the disposed-controller crash in manual testing — the
    // stale TabBar's GestureDetector was still wired to the old
    // controller).
    await tester.tap(find.text('JetStream'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Key-Value Stores'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Object Store'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling just one of JetStream/Key-Value/Object Store off and on works',
      (tester) async {
    await pumpDisconnectedApp(tester);

    await openSettings(tester);
    await tester.tap(find.byType(Switch).at(1)); // JetStream off
    await saveSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('JetStream'), findsNothing);
    expect(find.text('Key-Value Stores'), findsOneWidget);
    expect(find.text('Object Store'), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.byType(Switch).at(1)); // JetStream back on
    await saveSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('JetStream'), findsOneWidget);
    expect(find.text('Key-Value Stores'), findsOneWidget);
    expect(find.text('Object Store'), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.byType(Switch).at(3)); // Object Store off
    await saveSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('JetStream'), findsOneWidget);
    expect(find.text('Key-Value Stores'), findsOneWidget);
    expect(find.text('Object Store'), findsNothing);

    await openSettings(tester);
    await tester.tap(find.byType(Switch).at(3)); // Object Store back on
    await saveSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('JetStream'), findsOneWidget);
    expect(find.text('Key-Value Stores'), findsOneWidget);
    expect(find.text('Object Store'), findsOneWidget);
  });
}
