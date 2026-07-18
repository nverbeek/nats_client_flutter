import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/kv_dashboard.dart';
import 'package:nats_client_flutter/kv_manager.dart';

/// Test double for [KvManager], mirroring `FakeJetStreamManager` in
/// `test/jetstream_dashboard_test.dart`: `Client` can't be faked directly,
/// but none of [KvManager]'s methods are `final`, so overriding them here
/// lets widget tests drive the dashboard's connected states without a live
/// server.
class FakeKvManager extends KvManager {
  FakeKvManager() : super(Client());

  Future<String?> Function() checkAvailabilityImpl = () async => null;
  Future<List<StreamInfo>> Function() listBucketsImpl = () async => [];
  Future<void> Function(String)? deleteBucketImpl;
  Future<List<String>> Function(String) listKeysImpl = (_) async => [];
  Future<KeyValueEntry?> Function(String, String)? getEntryImpl;
  Future<int> Function(String, String, String)? putValueImpl;
  Future<int> Function(String, String, String, int)? updateValueImpl;
  Future<bool> Function(String, String)? deleteKeyImpl;
  Future<bool> Function(String, String)? purgeKeyImpl;
  Future<List<KeyValueEntry>> Function(String, String)? keyHistoryImpl;

  Future<AccountInfo> Function()? fetchAccountInfoImpl;

  int checkAvailabilityCalls = 0;
  int listBucketsCalls = 0;
  int deleteBucketCalls = 0;
  int fetchAccountInfoCalls = 0;
  String? lastCreatedBucket;
  int? lastCreatedHistory;
  Duration? lastCreatedTtl;
  int? lastCreatedReplicas;
  String? lastPutKey;
  String? lastPutValue;
  String? lastUpdateKey;
  String? lastUpdateValue;
  int? lastUpdateRevision;
  String? lastDeletedKey;
  String? lastPurgedKey;

  final Map<String, StreamController<KeyValueEntry?>> _watchControllers = {};
  final Map<String, int> _watchListenerCounts = {};

  /// Number of currently-active listeners on `bucket`'s watch stream --
  /// lets a test assert that a bucket switch or a refresh never leaves more
  /// than one live subscription stacked underneath another.
  int watchListenerCount(String bucket) => _watchListenerCounts[bucket] ?? 0;

  StreamController<KeyValueEntry?> watchControllerFor(String bucket) =>
      _watchControllers.putIfAbsent(
          bucket,
          () => StreamController<KeyValueEntry?>.broadcast(
                onListen: () => _watchListenerCounts[bucket] =
                    (_watchListenerCounts[bucket] ?? 0) + 1,
                onCancel: () => _watchListenerCounts[bucket] =
                    (_watchListenerCounts[bucket] ?? 0) - 1,
              ));

  @override
  Future<String?> checkAvailability({Duration? timeout}) {
    checkAvailabilityCalls++;
    return checkAvailabilityImpl();
  }

  @override
  Future<AccountInfo> fetchAccountInfo({Duration? timeout}) {
    fetchAccountInfoCalls++;
    return fetchAccountInfoImpl!();
  }

  @override
  Future<List<StreamInfo>> listBuckets({Duration? timeout}) {
    listBucketsCalls++;
    return listBucketsImpl();
  }

  @override
  Future<void> createBucket(String bucket,
      {int history = 1,
      Duration? ttl,
      int replicas = 1,
      String storage = 'file',
      Duration? timeout}) async {
    lastCreatedBucket = bucket;
    lastCreatedHistory = history;
    lastCreatedTtl = ttl;
    lastCreatedReplicas = replicas;
  }

  @override
  Future<void> deleteBucket(String bucket, {Duration? timeout}) async {
    deleteBucketCalls++;
    if (deleteBucketImpl != null) return deleteBucketImpl!(bucket);
  }

  @override
  Future<List<String>> listKeys(String bucket, {Duration? timeout}) {
    return listKeysImpl(bucket);
  }

  @override
  Future<KeyValueEntry?> getEntry(String bucket, String key) {
    if (getEntryImpl != null) return getEntryImpl!(bucket, key);
    return Future.value(null);
  }

  @override
  Future<int> putValue(String bucket, String key, String value) async {
    lastPutKey = key;
    lastPutValue = value;
    if (putValueImpl != null) return putValueImpl!(bucket, key, value);
    return 1;
  }

  @override
  Future<int> updateValue(
      String bucket, String key, String value, int expectedRevision) async {
    lastUpdateKey = key;
    lastUpdateValue = value;
    lastUpdateRevision = expectedRevision;
    if (updateValueImpl != null) {
      return updateValueImpl!(bucket, key, value, expectedRevision);
    }
    return expectedRevision + 1;
  }

  @override
  Future<bool> deleteKey(String bucket, String key) async {
    lastDeletedKey = key;
    if (deleteKeyImpl != null) return deleteKeyImpl!(bucket, key);
    return true;
  }

  @override
  Future<bool> purgeKey(String bucket, String key) async {
    lastPurgedKey = key;
    if (purgeKeyImpl != null) return purgeKeyImpl!(bucket, key);
    return true;
  }

  @override
  Future<List<KeyValueEntry>> keyHistory(String bucket, String key,
      {Duration? timeout}) {
    if (keyHistoryImpl != null) return keyHistoryImpl!(bucket, key);
    return Future.value([]);
  }

  @override
  Stream<KeyValueEntry?> watch(String bucket) => watchControllerFor(bucket).stream;
}

StreamInfo _bucketStream(String bucket, {int messages = 0, int bytes = 0}) {
  return StreamInfo(
    type: 'io.nats.jetstream.api.v1.stream_info_response',
    config: StreamConfig(name: 'KV_$bucket', subjects: ['\$KV.$bucket.>']),
    created: DateTime.now().toIso8601String(),
    state: StreamState(
      messages: messages,
      bytes: bytes,
      firstSeq: 1,
      firstTs: DateTime.now().toIso8601String(),
      lastSeq: messages,
      lastTs: DateTime.now().toIso8601String(),
      consumerCount: 0,
    ),
  );
}

KeyValueEntry _entry(String key, String value,
    {int revision = 1, KeyValueOp op = KeyValueOp.put}) {
  return KeyValueEntry(
    key: key,
    value: Uint8List.fromList(utf8.encode(value)),
    revision: revision,
    created: DateTime.now(),
    op: op,
  );
}

/// Asserts a confirm-dialog `TextButton` is styled with the theme's error
/// color -- the visual emphasis a destructive Delete/Purge action should
/// carry.
void expectErrorColoredButton(WidgetTester tester, Finder buttonFinder) {
  final button = tester.widget<TextButton>(buttonFinder);
  final colorScheme = Theme.of(tester.element(buttonFinder)).colorScheme;
  expect(button.style?.foregroundColor?.resolve(<WidgetState>{}),
      colorScheme.error);
}

void main() {
  testWidgets('shows a connect prompt when there is no active manager',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KvDashboard(manager: null))),
    );

    expect(find.text('Connect to a NATS server to use Key-Value stores.'),
        findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('shows a loading state while checking availability',
      (tester) async {
    final availability = Completer<String?>();
    final manager = FakeKvManager();
    manager.checkAvailabilityImpl = () => availability.future;

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pump();

    expect(find.text('Checking Key-Value availability...'), findsOneWidget);

    availability.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('shows a friendly error with retry when unavailable',
      (tester) async {
    final manager = FakeKvManager();
    manager.checkAvailabilityImpl =
        () async => 'This server or account does not have JetStream enabled.';

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This server or account does not have JetStream enabled.'),
      findsOneWidget,
    );
    expect(manager.checkAvailabilityCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(manager.checkAvailabilityCalls, 2);
  });

  testWidgets('lists buckets once available', (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [
          _bucketStream('app-config', messages: 3, bytes: 512),
          _bucketStream('user-features'),
        ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(find.text('app-config'), findsOneWidget);
    expect(find.text('user-features'), findsOneWidget);
    expect(find.textContaining('3 ops'), findsOneWidget);
    expect(find.text('Select a bucket to see its keys.'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no buckets',
      (tester) async {
    final manager = FakeKvManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(
        find.text('No KV buckets found on this account.'), findsOneWidget);
  });

  testWidgets('selecting a bucket loads and displays its keys',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port'];
    manager.getEntryImpl = (_, key) async => _entry(key, '5432');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    expect(find.text('db.port'), findsOneWidget);
    expect(find.textContaining('5432'), findsOneWidget);
    expect(find.textContaining('Rev #1'), findsOneWidget);
  });

  testWidgets('shows an empty state when the bucket has no keys',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    expect(find.text('No keys in this bucket yet.'), findsOneWidget);
  });

  testWidgets('Search Keys narrows the key list', (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port', 'db.host', 'feature.x'];
    manager.getEntryImpl = (_, key) async => _entry(key, 'v');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    expect(find.text('db.port'), findsOneWidget);
    expect(find.text('db.host'), findsOneWidget);
    expect(find.text('feature.x'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search keys'), 'db.');
    await tester.pumpAndSettle();

    expect(find.text('db.port'), findsOneWidget);
    expect(find.text('db.host'), findsOneWidget);
    expect(find.text('feature.x'), findsNothing);
  });

  testWidgets('Create Bucket dialog creates a bucket via the manager',
      (tester) async {
    final manager = FakeKvManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Bucket'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'app-config');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(manager.lastCreatedBucket, 'app-config');
    expect(find.text('Bucket "app-config" created.'), findsOneWidget);
  });

  testWidgets('Delete bucket confirms then calls the manager',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete bucket'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bucket?'), findsOneWidget);
    expectErrorColoredButton(tester, find.widgetWithText(TextButton, 'Delete'));

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(manager.deleteBucketCalls, 1);
    expect(find.text('Bucket "app-config" deleted.'), findsOneWidget);
  });

  testWidgets(
      'a mutation failure shows an error SnackBar with contrast-safe (onError) text',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.deleteBucketImpl = (_) async => throw Exception('delete boom');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete bucket'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final colorScheme = Theme.of(tester.element(find.byType(SnackBar))).colorScheme;
    expect(snackBar.backgroundColor, colorScheme.error);
    final content = snackBar.content as Text;
    expect(content.style?.color, colorScheme.onError);
  });

  testWidgets('Put Value dialog creates a key via the manager',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Put Value'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Key'), 'db.port');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Value'), '5432');
    await tester.tap(find.widgetWithText(TextButton, 'Put'));
    await tester.pumpAndSettle();

    expect(manager.lastPutKey, 'db.port');
    expect(manager.lastPutValue, '5432');
    expect(find.text('Key "db.port" saved.'), findsOneWidget);
  });

  testWidgets('Edit updates a key with its revision via the manager',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port'];
    manager.getEntryImpl = (_, key) async => _entry(key, '5432', revision: 3);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('db.port'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Value'), '5433');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(manager.lastUpdateKey, 'db.port');
    expect(manager.lastUpdateValue, '5433');
    expect(manager.lastUpdateRevision, 3);
    expect(find.text('Key "db.port" updated.'), findsOneWidget);
  });

  testWidgets('Delete key confirms then calls the manager and removes the row',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port'];
    manager.getEntryImpl = (_, key) async => _entry(key, '5432');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete Key?'), findsOneWidget);
    expectErrorColoredButton(tester, find.widgetWithText(TextButton, 'Delete'));

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(manager.lastDeletedKey, 'db.port');
    expect(find.text('Key "db.port" deleted.'), findsOneWidget);
    expect(find.text('No keys in this bucket yet.'), findsOneWidget);
  });

  testWidgets('Purge key confirms then calls the manager', (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port'];
    manager.getEntryImpl = (_, key) async => _entry(key, '5432');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purge').last);
    await tester.pumpAndSettle();
    expect(find.text('Purge Key?'), findsOneWidget);
    expectErrorColoredButton(tester, find.widgetWithText(TextButton, 'Purge'));

    await tester.tap(find.widgetWithText(TextButton, 'Purge'));
    await tester.pumpAndSettle();

    expect(manager.lastPurgedKey, 'db.port');
    expect(find.text('Key "db.port" purged.'), findsOneWidget);
  });

  testWidgets('live watch() updates add and remove keys', (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port'];
    manager.getEntryImpl = (_, key) async => _entry(key, '5432');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    expect(find.text('db.port'), findsOneWidget);
    expect(find.text('feature.x'), findsNothing);

    manager
        .watchControllerFor('app-config')
        .add(_entry('feature.x', 'true', revision: 5));
    await tester.pumpAndSettle();
    expect(find.text('feature.x'), findsOneWidget);

    manager.watchControllerFor('app-config').add(
        _entry('db.port', '', revision: 6, op: KeyValueOp.delete));
    await tester.pumpAndSettle();
    expect(find.text('db.port'), findsNothing);
  });

  testWidgets(
      'a watch stream error surfaces via the key-list error/Retry state '
      'instead of dying silently', (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl = () async => [_bucketStream('app-config')];
    manager.listKeysImpl = (_) async => ['db.port'];
    manager.getEntryImpl = (_, key) async => _entry(key, '5432');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    expect(find.text('db.port'), findsOneWidget);
    expect(manager.watchListenerCount('app-config'), 1);

    manager.watchControllerFor('app-config').addError(Exception('watch boom'));
    await tester.pumpAndSettle();

    // Without the onError handler, this would be an uncaught zone error and
    // the key list would just stop updating while looking perfectly healthy
    // -- instead it surfaces through the same error/Retry state a load
    // failure would.
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('watch boom'), findsOneWidget);
    // The errored subscription must actually be cancelled, not just have its
    // reference dropped -- otherwise it lingers uncancelled underneath
    // whatever Retry establishes next (a stacked/leaked subscription).
    expect(manager.watchListenerCount('app-config'), 0);

    // Retry re-establishes a fresh watch, not stacked on the dead one.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('db.port'), findsOneWidget);
    expect(manager.watchListenerCount('app-config'), 1);
  });

  testWidgets(
      'exactly one active watch survives a keys-load failure, Retry, and a '
      'bucket reselect',
      (tester) async {
    final manager = FakeKvManager();
    manager.listBucketsImpl =
        () async => [_bucketStream('app-config'), _bucketStream('other')];
    var failFirstLoad = true;
    manager.listKeysImpl = (_) async {
      if (failFirstLoad) {
        failFirstLoad = false;
        throw Exception('boom');
      }
      return ['db.port'];
    };
    manager.getEntryImpl = (_, key) async => _entry(key, '5432');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();

    // The failed load never reached `_startWatch` at all.
    expect(find.text('Retry'), findsOneWidget);
    expect(manager.watchListenerCount('app-config'), 0);

    // `_loadKeys`'s Retry button reaches `_startWatch` directly, without
    // going through `_selectBucket`'s own cancel-first step -- the path
    // `_startWatch`'s own cancel-before-listen guards against stacking a
    // second subscription on top of a still-active one.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('db.port'), findsOneWidget);
    expect(manager.watchListenerCount('app-config'), 1);

    // Switching to another bucket and back re-selects the same bucket --
    // still exactly one active watch, not stacked on the previous one.
    await tester.tap(find.text('other'));
    await tester.pumpAndSettle();
    expect(manager.watchListenerCount('app-config'), 0);
    await tester.tap(find.text('app-config'));
    await tester.pumpAndSettle();
    expect(manager.watchListenerCount('app-config'), 1);
  });

  testWidgets(
      'Account info button shows the cached snapshot without refetching',
      (tester) async {
    final manager = FakeKvManager();
    manager.lastAccountInfo = AccountInfo(
      domain: '',
      api: APIStats(level: 0, total: 4, errors: 0, inflight: 0),
      tier: Tier(
        memory: 512,
        storage: 1024,
        reservedMemory: 0,
        reservedStorage: 0,
        streams: 2,
        consumers: 0,
      ),
      tiers: const {},
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: KvDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Account Info'), findsOneWidget);
    expect(find.text('2 streams'), findsOneWidget);
    expect(manager.fetchAccountInfoCalls, 0);
  });
}
