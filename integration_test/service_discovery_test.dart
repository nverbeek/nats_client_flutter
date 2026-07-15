import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/nats_test_app.dart';

/// Exercises Milestone 18 (Service Discovery) against a real, locally-running
/// `nats-server` (no JetStream needed — the ADR-32 Services API is plain
/// core NATS pub/sub, see the fork's `lib/src/micro.dart`).
///
/// There's no practical way to stand up a real `nats.go`-hosted
/// microservice from Dart-only CI, so this stands up a minimal fake service
/// using the fork's own `Client.addService()` (the hosting half of the same
/// ADR-32 module `discoverServices()`/`getServicesInfo()`/`getServicesStats()`
/// were added to discover) — that's still a real, independent `dart_nats`
/// client on the wire replying to `$SRV.PING`/`INFO`/`STATS`, exactly as any
/// other ADR-32-conformant service would.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'enable Service Discovery -> Discover finds a live service -> detail shows endpoints/stats -> stopping the service makes it vanish on rediscovery',
      (tester) async {
    await pumpConnectedApp(tester);
    addTearDown(() => disconnectApp(tester));

    final runId = DateTime.now().microsecondsSinceEpoch;
    final serviceName = 'it-discovery-svc-$runId';

    // Service Discovery defaults off -- turn it on via Settings, the same
    // path a real user would take.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    final serviceDiscoverySwitch = find.byType(Switch).at(4);
    await tester.ensureVisible(serviceDiscoverySwitch);
    await tester.tap(serviceDiscoverySwitch);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Services'), findsOneWidget);
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    // No services running yet.
    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();
    expect(find.text(serviceName), findsNothing);

    // Stand up a real, independent ADR-32 service instance.
    final serviceClient = Client();
    await serviceClient.connect(Uri.parse('nats://localhost:4222'),
        retry: false);
    var handledRequests = 0;
    final service = await serviceClient.addService(ServiceConfig(
      name: serviceName,
      version: '1.0.0',
      description: 'Integration test service',
      endpoints: [
        Endpoint(
          name: 'ping',
          subject: 'it.discovery.$runId.ping',
          handler: (msg) {
            handledRequests++;
            msg.respondString('pong');
          },
        ),
      ],
    ));
    addTearDown(() async {
      await service.stop();
      await serviceClient.close();
    });

    // Drive one request through the endpoint before discovering, so STATS
    // has something non-zero to show.
    final callerClient = Client();
    await callerClient.connect(Uri.parse('nats://localhost:4222'),
        retry: false);
    await callerClient.requestString('it.discovery.$runId.ping', '');
    await callerClient.close();
    expect(handledRequests, 1);

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();
    expect(find.text(serviceName), findsOneWidget);

    await tester.tap(find.text(serviceName));
    await tester.pumpAndSettle();

    expect(find.text('$serviceName (v1.0.0)'), findsOneWidget);
    expect(find.text('Integration test service'), findsOneWidget);
    expect(find.text('ping'), findsOneWidget);
    expect(find.textContaining('1 req'), findsOneWidget);
    expect(find.textContaining('0 err'), findsOneWidget);

    // Stop the service before it's torn down by addTearDown, then confirm a
    // fresh Discover no longer finds it -- discovery is a snapshot, not a
    // live view.
    await service.stop();
    await serviceClient.close();

    await tester.tap(find.byKey(const ValueKey('discoverServicesButton')));
    await tester.pumpAndSettle();
    expect(find.text(serviceName), findsNothing);
  });
}
