import 'dart:async';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/object_store_dashboard.dart';
import 'package:nats_client_flutter/object_store_manager.dart';

/// Test double for [ObjectStoreManager], mirroring `FakeKvManager` in
/// `test/kv_dashboard_test.dart`: `Client` can't be faked directly, but none
/// of [ObjectStoreManager]'s methods are `final`, so overriding them here
/// lets widget tests drive the dashboard's connected states without a live
/// server.
class FakeObjectStoreManager extends ObjectStoreManager {
  FakeObjectStoreManager() : super(Client());

  Future<String?> Function() checkAvailabilityImpl = () async => null;
  Future<List<StreamInfo>> Function() listBucketsImpl = () async => [];
  Future<bool> Function(String)? deleteBucketImpl;
  Future<List<ObjectInfo>> Function(String) listObjectsImpl = (_) async => [];
  Future<ObjectInfo> Function(String, String, Uint8List)? putObjectImpl;
  Future<Uint8List?> Function(String, String)? getObjectImpl;
  Future<bool> Function(String, String)? deleteObjectImpl;

  int checkAvailabilityCalls = 0;
  int listBucketsCalls = 0;
  int deleteBucketCalls = 0;
  int listObjectsCalls = 0;
  String? lastCreatedBucket;
  String? lastCreatedStorage;
  int? lastCreatedReplicas;
  int? lastCreatedMaxBytes;
  Duration? lastCreatedTtl;
  String? lastPutName;
  Uint8List? lastPutBytes;
  String? lastDeletedObject;

  @override
  Future<String?> checkAvailability({Duration? timeout}) {
    checkAvailabilityCalls++;
    return checkAvailabilityImpl();
  }

  @override
  Future<List<StreamInfo>> listBuckets({Duration? timeout}) {
    listBucketsCalls++;
    return listBucketsImpl();
  }

  @override
  Future<void> createBucket(
    String bucket, {
    String storage = 'file',
    int replicas = 1,
    int maxBytes = -1,
    Duration? ttl,
    Duration? timeout,
  }) async {
    lastCreatedBucket = bucket;
    lastCreatedStorage = storage;
    lastCreatedReplicas = replicas;
    lastCreatedMaxBytes = maxBytes;
    lastCreatedTtl = ttl;
  }

  @override
  Future<bool> deleteBucket(String bucket, {Duration? timeout}) async {
    deleteBucketCalls++;
    if (deleteBucketImpl != null) return deleteBucketImpl!(bucket);
    return true;
  }

  @override
  Future<List<ObjectInfo>> listObjects(String bucket) {
    listObjectsCalls++;
    return listObjectsImpl(bucket);
  }

  @override
  Future<ObjectInfo> putObject(String bucket, String name, Uint8List data) async {
    lastPutName = name;
    lastPutBytes = data;
    if (putObjectImpl != null) return putObjectImpl!(bucket, name, data);
    return _objectInfo(name, data.length);
  }

  @override
  Future<Uint8List?> getObject(String bucket, String name) {
    if (getObjectImpl != null) return getObjectImpl!(bucket, name);
    return Future.value(null);
  }

  @override
  Future<bool> deleteObject(String bucket, String name) async {
    lastDeletedObject = name;
    if (deleteObjectImpl != null) return deleteObjectImpl!(bucket, name);
    return true;
  }
}

StreamInfo _bucketStream(String bucket, {int messages = 0, int bytes = 0}) {
  return StreamInfo(
    type: 'io.nats.jetstream.api.v1.stream_info_response',
    config: StreamConfig(name: 'OBJ_$bucket', subjects: ['\$O.$bucket.>']),
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

ObjectInfo _objectInfo(String name, int size,
    {int chunks = 1, String digest = 'SHA-256=abcdef1234567890'}) {
  return ObjectInfo(
    name: name,
    bucket: 'documents',
    nuid: 'nuid-$name',
    size: size,
    mtime: DateTime.now(),
    chunks: chunks,
    digest: digest,
  );
}

void main() {
  testWidgets('shows a connect prompt when there is no active manager',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
          home: Scaffold(body: ObjectStoreDashboard(manager: null))),
    );

    expect(find.text('Connect to a NATS server to use Object Store.'),
        findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('shows a loading state while checking availability',
      (tester) async {
    final availability = Completer<String?>();
    final manager = FakeObjectStoreManager();
    manager.checkAvailabilityImpl = () => availability.future;

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pump();

    expect(find.text('Checking Object Store availability...'), findsOneWidget);

    availability.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('shows a friendly error with retry when unavailable',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.checkAvailabilityImpl =
        () async => 'This server or account does not have JetStream enabled.';

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
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
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [
          _bucketStream('documents', messages: 2, bytes: 2048),
          _bucketStream('backups'),
        ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(find.text('documents'), findsOneWidget);
    expect(find.text('backups'), findsOneWidget);
    expect(find.textContaining('2 msgs'), findsOneWidget);
    expect(find.text('Select a bucket to see its objects.'), findsOneWidget);
    expect(
        find.textContaining('EXPERIMENTAL feature'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no buckets',
      (tester) async {
    final manager = FakeObjectStoreManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    expect(find.text('No Object Store buckets found on this account.'),
        findsOneWidget);
  });

  testWidgets('selecting a bucket loads and displays its objects',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];
    manager.listObjectsImpl =
        (_) async => [_objectInfo('report.pdf', 4096, chunks: 1)];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsOneWidget);
    expect(find.textContaining('1 chunk'), findsOneWidget);
  });

  testWidgets('shows an empty state when the bucket has no objects',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    expect(find.text('No objects in this bucket yet.'), findsOneWidget);
  });

  testWidgets('Search Objects narrows the object list', (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];
    manager.listObjectsImpl = (_) async => [
          _objectInfo('report.pdf', 100),
          _objectInfo('report-final.pdf', 100),
          _objectInfo('photo.png', 100),
        ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('report-final.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Search objects'), 'report');
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('report-final.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsNothing);
  });

  testWidgets('Create Bucket dialog creates a bucket via the manager',
      (tester) async {
    final manager = FakeObjectStoreManager();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Bucket'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Bucket Name'), 'documents');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(manager.lastCreatedBucket, 'documents');
    expect(find.text('Bucket "documents" created.'), findsOneWidget);
  });

  testWidgets('Delete bucket confirms then calls the manager',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete bucket'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bucket?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(manager.deleteBucketCalls, 1);
    expect(find.text('Bucket "documents" deleted.'), findsOneWidget);
  });

  testWidgets(
      'a mutation failure shows an error SnackBar with contrast-safe (onError) text',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];
    manager.deleteBucketImpl = (_) async => throw Exception('delete boom');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
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

  testWidgets('Upload calls putObject via the injected file picker',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];
    final fakeBytes = Uint8List.fromList([1, 2, 3, 4]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ObjectStoreDashboard(
            manager: manager,
            pickUploadFile: () async => (fakeBytes, 'photo.png'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();

    expect(manager.lastPutName, 'photo.png');
    expect(manager.lastPutBytes, fakeBytes);
    expect(find.text('Uploaded "photo.png".'), findsOneWidget);
  });

  testWidgets('Upload does nothing if the file picker is cancelled',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ObjectStoreDashboard(
            manager: manager,
            pickUploadFile: () async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();

    expect(manager.lastPutName, isNull);
  });

  testWidgets('Download fetches bytes and hands them to the save callback',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];
    manager.listObjectsImpl = (_) async => [_objectInfo('report.pdf', 100)];
    final downloadedBytes = Uint8List.fromList([9, 9, 9]);
    manager.getObjectImpl = (_, __) async => downloadedBytes;

    String? savedName;
    Uint8List? savedBytes;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ObjectStoreDashboard(
            manager: manager,
            saveDownloadedFile: (name, bytes) async {
              savedName = name;
              savedBytes = bytes;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download'));
    await tester.pumpAndSettle();

    expect(savedName, 'report.pdf');
    expect(savedBytes, downloadedBytes);
    expect(find.text('Downloaded "report.pdf".'), findsOneWidget);
  });

  testWidgets('Delete object confirms then calls the manager and removes the row',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];
    manager.listObjectsImpl = (_) async => [_objectInfo('report.pdf', 100)];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Object?'), findsOneWidget);

    // After confirming, the fake's listObjectsImpl (re-fetched by the
    // dashboard, since there's no watch()) reflects the object being gone.
    manager.listObjectsImpl = (_) async => [];
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(manager.lastDeletedObject, 'report.pdf');
    expect(find.text('Object "report.pdf" deleted.'), findsOneWidget);
    expect(find.text('report.pdf'), findsNothing);
  });

  testWidgets('Refresh objects reloads the list (no live watch)',
      (tester) async {
    final manager = FakeObjectStoreManager();
    manager.listBucketsImpl = () async => [_bucketStream('documents')];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ObjectStoreDashboard(manager: manager))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('documents'));
    await tester.pumpAndSettle();

    final callsAfterSelect = manager.listObjectsCalls;
    expect(find.text('No objects in this bucket yet.'), findsOneWidget);

    manager.listObjectsImpl = (_) async => [_objectInfo('new-file.txt', 10)];
    await tester.tap(find.byTooltip('Refresh objects'));
    await tester.pumpAndSettle();

    expect(manager.listObjectsCalls, callsAfterSelect + 1);
    expect(find.text('new-file.txt'), findsOneWidget);
  });
}
