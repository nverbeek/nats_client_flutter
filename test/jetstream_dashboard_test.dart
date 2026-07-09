import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_dashboard.dart';

// `Client` from dart_nats is a concrete class backed by real socket/stream
// logic, not an injectable interface, so we can't stand up a fake connected
// client here without a live server. This test covers the one dashboard
// state that's fully reachable without a network connection (disconnected);
// the "JetStream unavailable" and "connected" dashboard states are verified
// manually against a real server — see AGENTS.md "Recipe E: Local
// JetStream Testing".
void main() {
  testWidgets('shows a connect prompt when there is no active client',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: JetStreamDashboard(client: null),
        ),
      ),
    );

    expect(find.text('Connect to a NATS server to use JetStream.'),
        findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
}
