import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/account_info_dialog.dart';

AccountInfo _accountInfo({
  String domain = '',
  int memory = 0,
  int storage = 0,
  int reservedMemory = 0,
  int reservedStorage = 0,
  int streams = 0,
  int consumers = 0,
  int total = 0,
  int errors = 0,
  int inflight = 0,
}) {
  return AccountInfo(
    domain: domain,
    api: APIStats(level: 0, total: total, errors: errors, inflight: inflight),
    tier: Tier(
      memory: memory,
      storage: storage,
      reservedMemory: reservedMemory,
      reservedStorage: reservedStorage,
      streams: streams,
      consumers: consumers,
    ),
    tiers: const {},
  );
}

Future<void> _pump(WidgetTester tester, AccountInfoDialog dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => dialog,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders cached data immediately without calling onRefresh',
      (tester) async {
    var refreshCalls = 0;
    await _pump(
      tester,
      AccountInfoDialog(
        initial: _accountInfo(
            domain: 'hub',
            memory: 1024,
            storage: 2048,
            reservedMemory: 4096,
            streams: 3,
            consumers: 5,
            total: 10,
            errors: 1,
            inflight: 2),
        onRefresh: () async {
          refreshCalls++;
          return _accountInfo();
        },
      ),
    );

    expect(find.text('Domain: hub'), findsOneWidget);
    expect(find.text('3 streams'), findsOneWidget);
    expect(find.text('5 consumers'), findsOneWidget);
    expect(find.text('Memory: 1.0 KB / 4.0 KB'), findsOneWidget);
    expect(find.text('Storage: 2.0 KB'), findsOneWidget);
    expect(find.textContaining('API calls: 10'), findsOneWidget);
    expect(refreshCalls, 0);
  });

  testWidgets('omits the usage bar when a tier has no reserved limit',
      (tester) async {
    await _pump(
      tester,
      AccountInfoDialog(
        initial: _accountInfo(storage: 2048, reservedStorage: 0),
        onRefresh: () async => _accountInfo(),
      ),
    );

    expect(find.text('Storage: 2.0 KB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
      'treats a huge reserved value (uint64 -1 "unlimited" sentinel) as unlimited too',
      (tester) async {
    await _pump(
      tester,
      AccountInfoDialog(
        initial:
            _accountInfo(storage: 2048, reservedStorage: 9223372036854775807),
        onRefresh: () async => _accountInfo(),
      ),
    );

    expect(find.text('Storage: 2.0 KB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('fetches fresh data via onRefresh when nothing is cached',
      (tester) async {
    var refreshCalls = 0;
    await _pump(
      tester,
      AccountInfoDialog(
        initial: null,
        onRefresh: () async {
          refreshCalls++;
          return _accountInfo(domain: 'fetched', streams: 7);
        },
      ),
    );

    expect(refreshCalls, 1);
    expect(find.text('Domain: fetched'), findsOneWidget);
    expect(find.text('7 streams'), findsOneWidget);
  });

  testWidgets('Refresh button re-fetches and replaces the displayed data',
      (tester) async {
    var refreshCalls = 0;
    await _pump(
      tester,
      AccountInfoDialog(
        initial: _accountInfo(streams: 1),
        onRefresh: () async {
          refreshCalls++;
          return _accountInfo(streams: 9);
        },
      ),
    );

    expect(find.text('1 streams'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(find.text('9 streams'), findsOneWidget);
    expect(find.text('1 streams'), findsNothing);
  });

  testWidgets('shows an error message when the initial fetch fails',
      (tester) async {
    await _pump(
      tester,
      AccountInfoDialog(
        initial: null,
        onRefresh: () async =>
            throw NatsException('jetstream not enabled for account'),
      ),
    );

    expect(
      find.text('This server or account does not have JetStream enabled.'),
      findsOneWidget,
    );
  });

  testWidgets('Close button dismisses the dialog', (tester) async {
    await _pump(
      tester,
      AccountInfoDialog(
        initial: _accountInfo(),
        onRefresh: () async => _accountInfo(),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Account Info'), findsNothing);
  });
}
