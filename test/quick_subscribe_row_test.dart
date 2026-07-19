import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/main.dart';
import 'package:nats_client_flutter/subscription_info.dart';

/// Milestone 25: "Subscribe to This Subject" row menu entry on Live Messages.
Widget buildApp() {
  return ChangeNotifierProvider<ThemeModel>(
    create: (_) => ThemeModel('dark'),
    child: MaterialApp(
      home: LoaderOverlay(
        child: MyHomePage(
          '1.0.0',
          'NATS Client',
          'nats://',
          '127.0.0.1',
          '4222',
          [SubscriptionInfo(subject: 'orders.>', colorIndex: 0)],
          const [],
        ),
      ),
    ),
  );
}

Message<dynamic> makeMessage(String subject, String payload, Client client,
    {int sid = 1}) {
  return Message<dynamic>(
      subject, sid, Uint8List.fromList(utf8.encode(payload)), client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAppAtDesktopSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'the row menu adds an exact-subject subscription and leaves the '
      'wildcard in place', (tester) async {
    await pumpAppAtDesktopSize(tester);

    final state = tester.state(find.byType(MyHomePage)) as dynamic;
    final client = Client();
    state.handleIncomingMessage(
        makeMessage('orders.created', 'hello world', client));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('hello world'), findsOneWidget);

    // Open the row's overflow menu and pick the new entry.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe to This Subject'), findsOneWidget);
    await tester.tap(find.text('Subscribe to This Subject'));
    await tester.pumpAndSettle();

    final subscriptions = state.subscriptions as List<SubscriptionInfo>;
    expect(subscriptions.any((s) => s.subject == 'orders.created'), isTrue,
        reason: 'A new exact subscription for the message subject should '
            'have been added');
    expect(subscriptions.any((s) => s.subject == 'orders.>'), isTrue,
        reason: 'The original wildcard subscription must not be removed');

    expect(find.textContaining('Subscribed to "orders.created"'),
        findsOneWidget,
        reason: 'A SnackBar should note the new subscription and that the '
            'wider one is still active');
  });

  testWidgets(
      'the row menu entry is hidden once an exact subscription for the '
      'subject already exists', (tester) async {
    await pumpAppAtDesktopSize(tester);

    final state = tester.state(find.byType(MyHomePage)) as dynamic;
    final client = Client();
    state.handleIncomingMessage(
        makeMessage('orders.created', 'hello world', client));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscribe to This Subject'));
    await tester.pumpAndSettle();

    // Re-open the same row's menu -- the entry should now be gone since an
    // exact subscription for 'orders.created' already exists.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe to This Subject'), findsNothing);
  });
}
