import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/server_monitor.dart';
import 'package:nats_client_flutter/server_monitor_dashboard.dart';

class FakeServerMonitorClient extends ServerMonitorClient {
  FakeServerMonitorClient() : super(DirectMonitorEndpoint('127.0.0.1', 8222));

  Future<ServerVarz> Function() varzImpl = () async => sampleVarz();
  Future<ConnzPage> Function(ConnzSort sort, int offset, int limit) connzImpl =
      (sort, offset, limit) async => samplePage(offset, limit);

  int varzCalls = 0;
  final List<(ConnzSort, int, int)> connzCalls = [];

  @override
  Future<ServerVarz> fetchVarz() {
    varzCalls++;
    return varzImpl();
  }

  @override
  Future<ConnzPage> fetchConnz(
      {required ConnzSort sort, int offset = 0, int limit = 25}) {
    connzCalls.add((sort, offset, limit));
    return connzImpl(sort, offset, limit);
  }

  @override
  Future<HealthStatus> fetchHealth() async => const HealthStatus(ok: true);

  @override
  Future<int> fetchGatewayCount() async => 0;
}

ServerVarz sampleVarz() => ServerVarz(
      serverId: 'NCXK7Q4ZJ2R5',
      serverName: 'nats-east-1',
      version: '2.11.4',
      goVersion: 'go1.24.3',
      host: '0.0.0.0',
      port: 4222,
      start: DateTime.utc(2026, 10, 31, 9),
      now: DateTime.utc(2026, 11, 3, 13),
      connections: 312,
      subscriptions: 4812,
      cpu: 12.4,
      mem: 88290918,
      cores: 8,
      routes: 2,
      leafnodes: 3,
      clusterName: 'east',
      jetStreamEnabled: true,
    );

ConnzPage samplePage(int offset, int limit) => ConnzPage(
      total: 60,
      offset: offset,
      limit: limit,
      connections: [
        for (var i = 0; i < (60 - offset).clamp(0, limit); i++)
          ConnSummary(
            cid: 1000 + offset + i,
            name: 'svc-${offset + i}',
            ip: '10.0.0.${i + 2}',
            port: 50000 + i,
            lang: 'go',
            version: '1.41.2',
            subscriptions: 3,
            inMsgs: 10,
            outMsgs: 20,
            uptime: const Duration(hours: 2),
          ),
      ],
    );

void main() {
  late FakeServerMonitorClient client;
  late ServerMonitorSession session;

  setUp(() {
    client = FakeServerMonitorClient();
    session = ServerMonitorSession(client);
  });

  Future<void> pump(WidgetTester tester,
      {double width = 1400,
      ServerMonitorSession? sessionOverride,
      bool noSession = false,
      VoidCallback? onOpenSettings}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerMonitorDashboard(
          session: noSession ? null : (sessionOverride ?? session),
          onOpenSettings: onOpenSettings,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// Unmounts the dashboard so its timers are cancelled before the test
  /// ends.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('asks to connect when there is no session', (tester) async {
    await pump(tester, noSession: true);
    expect(find.text('Connect to a NATS server to see its monitoring data.'),
        findsOneWidget);
    expect(client.varzCalls, 0);
  });

  testWidgets('shows identity, tiles and the first connections page',
      (tester) async {
    await pump(tester);

    expect(find.text('nats-east-1'), findsWidgets);
    expect(find.text('v2.11.4'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);
    expect(find.text('312'), findsOneWidget);
    expect(find.text('4,812'), findsOneWidget);
    expect(find.text('12.4%'), findsOneWidget);
    expect(find.text('east · 2 routes'), findsOneWidget);
    expect(find.text('svc-0'), findsOneWidget);
    expect(find.text('1–25 of 60'), findsOneWidget);
    // Sorted by messages out by default, so busy clients come first.
    expect(client.connzCalls.single, (ConnzSort.msgsTo, 0, 25));
    await unmount(tester);
  });

  testWidgets('tapping a sortable header asks the server to sort by it',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Msgs in'));
    await tester.pump();
    await tester.pump();
    expect(client.connzCalls.last, (ConnzSort.msgsFrom, 0, 25));
    await unmount(tester);
  });

  testWidgets('Name, Address and Client are not sortable', (tester) async {
    await pump(tester);
    final callsBefore = client.connzCalls.length;
    for (final header in ['Name', 'Address', 'Client']) {
      await tester.tap(find.descendant(
          of: find.byType(DataTable), matching: find.text(header)));
      await tester.pump();
    }
    expect(client.connzCalls.length, callsBefore);
    await unmount(tester);
  });

  testWidgets('next page requests the next offset', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    await tester.pump();
    expect(client.connzCalls.last, (ConnzSort.msgsTo, 25, 25));
    expect(find.text('26–50 of 60'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an endpoint that never answers shows how to fix it',
      (tester) async {
    var settingsOpened = false;
    client.varzImpl =
        () async => throw const MonitorException(MonitorErrorKind.unreachable);
    await pump(tester, onOpenSettings: () => settingsOpened = true);

    expect(find.text("Can't reach the monitoring endpoint"), findsOneWidget);
    expect(
        find.text('No response from http://127.0.0.1:8222.'), findsOneWidget);
    expect(find.textContaining('-m 8222'), findsOneWidget);

    await tester.tap(find.text('Change port'));
    expect(settingsOpened, isTrue);

    client.varzImpl = () async => sampleVarz();
    await tester.tap(find.text('Retry now'));
    await tester.pump();
    await tester.pump();
    expect(find.text('v2.11.4'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a failed poll after a good one keeps the data', (tester) async {
    await pump(tester);
    client.varzImpl =
        () async => throw const MonitorException(MonitorErrorKind.unreachable);
    await tester.tap(find.byTooltip('Refresh now'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Last update failed'), findsOneWidget);
    expect(find.text('312'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('polls on the interval, and pause stops it', (tester) async {
    await pump(tester);
    expect(client.varzCalls, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(client.varzCalls, 2);

    await tester.tap(find.byTooltip('Pause polling'));
    await tester.pump();
    expect(find.text('Polling paused'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(client.varzCalls, 2);

    await tester.tap(find.byTooltip('Resume polling'));
    await tester.pump();
    await tester.pump();
    expect(client.varzCalls, 3);
    await unmount(tester);
  });

  testWidgets('connz is polled every 5th time, not every time', (tester) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    }
    expect(client.varzCalls, 5);
    expect(client.connzCalls, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(client.connzCalls, hasLength(2));
    await unmount(tester);
  });

  testWidgets('the connections table is never narrower than its card',
      (tester) async {
    await pump(tester);
    final card = tester.getRect(find
        .ancestor(of: find.byType(DataTable), matching: find.byType(Card))
        .first);
    final table = tester.getRect(find.byType(DataTable));
    // At least the card's width. The test font draws every letter as a wide
    // square, so the exact fit is checked with real fonts in
    // integration_test/server_monitor_test.dart instead.
    expect(table.width, greaterThanOrEqualTo(card.width - 4));
    await unmount(tester);
  });

  testWidgets('page controls are at the top of the connections card',
      (tester) async {
    await pump(tester);
    final heading =
        tester.getRect(find.byKey(const ValueKey('connectionsHeading')));
    final next = tester.getRect(find.byTooltip('Next page'));
    final table = tester.getRect(find.byType(DataTable));
    expect(next.center.dy, closeTo(heading.center.dy, 12));
    expect(next.bottom, lessThanOrEqualTo(table.top));
    await unmount(tester);
  });

  testWidgets('updated, pause and refresh sit at the right of the header',
      (tester) async {
    await pump(tester);
    final name = tester.getRect(find.text('v2.11.4'));
    final refresh = tester.getRect(find.byTooltip('Refresh now'));
    final pause = tester.getRect(find.byTooltip('Pause polling'));
    final updated = tester.getRect(find.text('Updated just now'));
    // Same row as the pills, pushed to the right edge of the main panel.
    expect(refresh.center.dy, closeTo(name.center.dy, 12));
    expect(refresh.right, greaterThan(1400 - 40));
    expect(pause.right, lessThanOrEqualTo(refresh.left));
    expect(updated.right, lessThanOrEqualTo(pause.left));
    expect(updated.left, greaterThan(name.right + 200));
    await unmount(tester);
  });

  testWidgets('narrow: the actions get a row of their own', (tester) async {
    await pump(tester, width: 600);
    final pill = tester.getRect(find.text('v2.11.4'));
    final refresh = tester.getRect(find.byTooltip('Refresh now'));
    final updated = tester.getRect(find.text('Updated just now'));
    expect(refresh.top, greaterThan(pill.bottom));
    expect(updated.center.dy, closeTo(refresh.center.dy, 12));
    expect(updated.left, lessThan(100));
    expect(refresh.right, greaterThan(600 - 40));
    await unmount(tester);
  });

  testWidgets('wide: identity panel on the left, no Details toggle',
      (tester) async {
    await pump(tester, width: 1400);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Max payload'), findsOneWidget);
    expect(find.byKey(const ValueKey('serverDetailsToggle')), findsNothing);
    await unmount(tester);
  });

  testWidgets('medium: identity moves behind Details', (tester) async {
    await pump(tester, width: 900);
    expect(find.text('Server'), findsNothing);
    expect(find.text('Max payload'), findsNothing);
    expect(find.text('Topology'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('serverDetailsToggle')));
    await tester.pump();
    expect(find.text('Max payload'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('narrow: a sort picker and rows that expand', (tester) async {
    await pump(tester, width: 600);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('connzSortPicker')), findsOneWidget);
    // No table headers, so Address only shows once a row is opened.
    expect(find.text('Address'), findsNothing);

    await tester.scrollUntilVisible(find.text('svc-0'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('svc-0'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('10.0.0.2:50000'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a new session starts over', (tester) async {
    await pump(tester);
    expect(find.text('v2.11.4'), findsOneWidget);

    final other = FakeServerMonitorClient()
      ..varzImpl = () async => const ServerVarz(
          serverId: 'OTHER', serverName: 'nats-west-1', version: '2.12.0');
    await pump(tester, sessionOverride: ServerMonitorSession(other));
    expect(find.text('v2.12.0'), findsOneWidget);
    expect(find.text('v2.11.4'), findsNothing);
    await unmount(tester);
  });
}
