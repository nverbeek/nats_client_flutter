import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// The Server tab against a real `nats-server` started with monitoring on
/// (`-m 8222`, as CI's `test` job and AGENTS.md Recipe E do).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Server tab shows the real /varz and /connz, and re-sorts on the server',
      (tester) async {
    // Wide enough for the side-panel layout, so the table has headers.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpConnectedApp(tester, serverMonitorEnabled: true);
    addTearDown(() => disconnectApp(tester));

    await tester.tap(find.text('Server'));
    await pumpUntil(tester,
        () => find.textContaining('Polling every').evaluate().isNotEmpty);

    // The identity panel shows the real server's version from /varz.
    expect(find.text('Version'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^v\d+\.\d+')), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);

    // /connz lists at least the app's own connection.
    await pumpUntil(
        tester,
        () => find
            .textContaining(RegExp(r'^1–\d+ of \d+$'))
            .evaluate()
            .isNotEmpty);
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, isNotEmpty);

    // With real fonts the table fits the card exactly at this width: it
    // fills it, and needs no sideways scrolling.
    final card = tester.getRect(find
        .ancestor(of: find.byType(DataTable), matching: find.byType(Card))
        .first);
    expect(
        tester.getRect(find.byType(DataTable)).width, closeTo(card.width, 4));
    // Paging is at the top of the card, next to its title.
    expect(
        tester.getRect(find.byTooltip('Next page')).center.dy,
        closeTo(
            tester
                .getRect(find.byKey(const ValueKey('connectionsHeading')))
                .center
                .dy,
            12));

    // Sorting is the server's: the query line shows the new sort.
    final msgsIn = find.descendant(
        of: find.byType(DataTable), matching: find.text('Msgs in'));
    await tester.ensureVisible(msgsIn);
    await tester.pumpAndSettle();
    await tester.tap(msgsIn);
    await pumpUntil(
        tester,
        () =>
            find.textContaining('/connz?sort=msgs_from').evaluate().isNotEmpty);
    await pumpUntil(tester,
        () => tester.widget<DataTable>(find.byType(DataTable)).rows.isNotEmpty);
  });

  testWidgets('a closed monitoring port explains how to turn monitoring on',
      (tester) async {
    // Nothing listens on port 1.
    await pumpConnectedApp(tester,
        serverMonitorEnabled: true, serverMonitorPort: 1);
    addTearDown(() => disconnectApp(tester));

    await tester.tap(find.text('Server'));
    await pumpUntil(
        tester,
        () => find
            .text("Can't reach the monitoring endpoint")
            .evaluate()
            .isNotEmpty);
    expect(find.textContaining('-m 8222'), findsOneWidget);
    // The NATS connection itself is unaffected.
    expect(find.text('Status: Connected'), findsOneWidget);
  });
}
