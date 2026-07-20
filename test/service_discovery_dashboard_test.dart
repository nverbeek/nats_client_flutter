import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/service_discovery_dashboard.dart';
import 'package:nats_client_flutter/service_discovery_manager.dart';

/// Test double for [ServiceDiscoveryManager], mirroring `FakeObjectStoreManager`
/// in `test/object_store_dashboard_test.dart`: `Client` can't be faked
/// directly, but none of [ServiceDiscoveryManager]'s methods are `final`, so
/// overriding them here lets widget tests drive the dashboard's discovered/
/// selected/error states without a live server.
class FakeServiceDiscoveryManager extends ServiceDiscoveryManager {
  FakeServiceDiscoveryManager() : super(Client());

  Future<List<PingResponse>> Function() discoverImpl = () async => [];
  Future<InfoResponse?> Function(String, String) fetchInfoImpl =
      (_, __) async => null;
  Future<StatsResponse?> Function(String, String) fetchStatsImpl =
      (_, __) async => null;

  int discoverCalls = 0;

  @override
  Future<List<PingResponse>> discover({Duration? timeout}) {
    discoverCalls++;
    return discoverImpl();
  }

  @override
  Future<InfoResponse?> fetchInfo(String name, String id, {Duration? timeout}) {
    return fetchInfoImpl(name, id);
  }

  @override
  Future<StatsResponse?> fetchStats(String name, String id,
      {Duration? timeout}) {
    return fetchStatsImpl(name, id);
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows connect prompt when there is no manager', (tester) async {
    await tester
        .pumpWidget(wrap(const ServiceDiscoveryDashboard(manager: null)));

    expect(find.text('Connect to a NATS server to use Service Discovery.'),
        findsOneWidget);
  });

  testWidgets('shows a prompt to discover before Discover is tapped',
      (tester) async {
    final manager = FakeServiceDiscoveryManager();
    await tester.pumpWidget(wrap(ServiceDiscoveryDashboard(manager: manager)));

    expect(find.text('Tap Discover to find running services.'), findsOneWidget);
    expect(manager.discoverCalls, 0);
  });

  testWidgets('Discover populates the service list', (tester) async {
    final manager = FakeServiceDiscoveryManager()
      ..discoverImpl = () async => [
            PingResponse(id: 'inst-1', name: 'orders', version: '1.0.0'),
            PingResponse(id: 'inst-2', name: 'billing', version: '2.1.0'),
          ];
    await tester.pumpWidget(wrap(ServiceDiscoveryDashboard(manager: manager)));

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();

    expect(manager.discoverCalls, 1);
    // Sorted by name: billing before orders.
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['billing', 'orders']);
  });

  testWidgets('discovering nothing shows the empty state', (tester) async {
    final manager = FakeServiceDiscoveryManager();
    await tester.pumpWidget(wrap(ServiceDiscoveryDashboard(manager: manager)));

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No services responded'), findsOneWidget);
  });

  testWidgets('a discovery error shows the error state with Retry',
      (tester) async {
    final manager = FakeServiceDiscoveryManager()
      ..discoverImpl = () async => throw NatsException('not connected');
    await tester.pumpWidget(wrap(ServiceDiscoveryDashboard(manager: manager)));

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();

    expect(find.text('not connected'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('selecting a service loads its endpoints and stats',
      (tester) async {
    final manager = FakeServiceDiscoveryManager();
    manager.discoverImpl = () async =>
        [PingResponse(id: 'inst-1', name: 'orders', version: '1.0.0')];
    manager.fetchInfoImpl = (name, id) async => InfoResponse(
          id: id,
          name: name,
          version: '1.0.0',
          description: 'Order processing service',
          endpoints: [
            EndpointInfo(name: 'create', subject: 'orders.create'),
          ],
        );
    manager.fetchStatsImpl = (name, id) async => StatsResponse(
          id: id,
          name: name,
          version: '1.0.0',
          started: DateTime.now().toUtc(),
          endpoints: [
            EndpointStatsInfo(
              name: 'create',
              subject: 'orders.create',
              numRequests: 5,
              numErrors: 1,
              averageProcessingTimeNs: 2500000,
            ),
          ],
        );
    await tester.pumpWidget(wrap(ServiceDiscoveryDashboard(manager: manager)));

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    expect(find.text('orders (v1.0.0)'), findsOneWidget);
    expect(find.text('Order processing service'), findsOneWidget);
    expect(find.text('create'), findsOneWidget);
    expect(find.textContaining('5 req'), findsOneWidget);
    expect(find.textContaining('1 err'), findsOneWidget);
    expect(find.textContaining('2.5 ms'), findsOneWidget);
  });

  testWidgets(
      'selecting a service that stopped responding shows a "no longer responding" message',
      (tester) async {
    final manager = FakeServiceDiscoveryManager()
      ..discoverImpl = () async => [
            PingResponse(id: 'inst-1', name: 'orders', version: '1.0.0'),
          ];
    await tester.pumpWidget(wrap(ServiceDiscoveryDashboard(manager: manager)));

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('orders'));
    await tester.pumpAndSettle();

    expect(find.textContaining('is no longer responding'), findsOneWidget);
  });

  testWidgets('resets state when the manager changes to null (disconnect)',
      (tester) async {
    final manager = FakeServiceDiscoveryManager()
      ..discoverImpl = () async => [
            PingResponse(id: 'inst-1', name: 'orders', version: '1.0.0'),
          ];
    final key = GlobalKey<ServiceDiscoveryDashboardState>();
    await tester.pumpWidget(
        wrap(ServiceDiscoveryDashboard(key: key, manager: manager)));

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();
    expect(find.text('orders'), findsOneWidget);

    await tester
        .pumpWidget(wrap(ServiceDiscoveryDashboard(key: key, manager: null)));
    await tester.pumpAndSettle();

    expect(find.text('Connect to a NATS server to use Service Discovery.'),
        findsOneWidget);
  });
}
