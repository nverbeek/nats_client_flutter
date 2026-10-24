import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nats_client_flutter/connection_history.dart';
import 'package:nats_client_flutter/main.dart';
import 'package:nats_client_flutter/subscription_info.dart';
import 'package:nats_client_flutter/tcp_relay.dart';

/// The Docker image's NATS CLI contexts in the Host dropdown. The app only
/// fetches them in the Docker web build, so these tests hand the contexts to
/// the page directly.
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
          [SubscriptionInfo(subject: '>', colorIndex: 0)],
          const [
            ConnectionHistoryEntry(
                scheme: 'nats://', host: 'old-host', port: '4222'),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<dynamic> pumpWithContexts(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(MyHomePage)) as dynamic;
    state.setState(() {
      state.relayContexts = const [
        RelayContext(
            name: 'prod',
            description: 'Production',
            server: 'tls://nats-prod:4333'),
        RelayContext(
            name: 'broken',
            server: 'nats://nats-x:4222',
            error: 'creds file "a.creds" was not found'),
      ];
    });
    await tester.pumpAndSettle();
    return state;
  }

  Finder hostField() => find.widgetWithText(TextFormField, '127.0.0.1');

  testWidgets('lists contexts above the history, with their problems',
      (tester) async {
    await pumpWithContexts(tester);
    await tester.tap(hostField());
    await tester.pumpAndSettle();

    expect(find.text('Context: prod'), findsOneWidget);
    expect(find.text('Production - tls://nats-prod:4333'), findsOneWidget);
    expect(find.text('Context: broken'), findsOneWidget);
    expect(find.textContaining('Unusable: creds file'), findsOneWidget);
    expect(find.text('nats://old-host:4222'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Context: prod')).dy <
            tester.getTopLeft(find.text('nats://old-host:4222')).dy,
        isTrue,
        reason: 'contexts come first');
  });

  testWidgets('picking a context fills the fields and marks the Host label',
      (tester) async {
    final state = await pumpWithContexts(tester);
    await tester.tap(hostField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context: prod'));
    await tester.pumpAndSettle();

    expect(find.text('Host (context: prod)'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'nats-prod'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '4333'), findsOneWidget);
    expect((state.selectedRelayContext as RelayContext).name, 'prod');
  });

  testWidgets('an unusable context cannot be picked', (tester) async {
    final state = await pumpWithContexts(tester);
    await tester.tap(hostField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context: broken'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(state.selectedRelayContext, isNull);
    expect(find.widgetWithText(TextFormField, '127.0.0.1'), findsOneWidget);

    // With the keyboard, Autocomplete selects it anyway: the field is put
    // back.
    await tester.enterText(hostField(), 'broken');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.selectedRelayContext, isNull);
    expect(state.host, 'broken', reason: 'what was typed');
    expect(find.widgetWithText(TextFormField, 'nats-x'), findsNothing);
  });

  testWidgets('editing the host turns it back into a plain connection',
      (tester) async {
    final state = await pumpWithContexts(tester);
    await tester.tap(hostField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context: prod'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'nats-prod'), 'somewhere-else');
    await tester.pumpAndSettle();
    expect(find.text('Host (context: prod)'), findsNothing);
    expect(state.selectedRelayContext, isNull);
  });

  testWidgets('Clear history keeps the contexts', (tester) async {
    await pumpWithContexts(tester);
    await tester.tap(hostField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();

    expect(find.text('nats://old-host:4222'), findsNothing);
    expect(find.text('Context: prod'), findsOneWidget);
    expect(find.text('Clear history'), findsNothing);
  });
}
