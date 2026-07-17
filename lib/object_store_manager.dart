import 'dart:async';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;

import 'jetstream_manager.dart' show describeJetStreamError;

/// Prefix JetStream uses for the backing stream of every Object Store
/// bucket. Bucket names shown in the UI have this stripped back off.
const String objectStoreStreamPrefix = 'OBJ_';

/// Thin, testable wrapper around a connected [Client] for Object Store
/// bucket monitoring and management, mirroring the shape of `KvManager`.
///
/// Unlike `KvManager`, bucket creation goes through the package's own
/// `ObjectStoreConfig.toStreamConfig()` (via `createObjectStore()`) rather
/// than building a `StreamConfig` by hand — live-server verification (see
/// ROADMAP.md's Milestone 7) confirmed, unlike `KeyValueConfig`'s equivalent
/// method, it does *not* drop `ttl`/replicas onto the floor.
class ObjectStoreManager {
  final Client client;

  ObjectStoreManager(this.client);

  JetStream get _js => client.jetStream();

  /// Returns `null` if JetStream (and therefore Object Store, which is built
  /// on top of it) is available on the current account, otherwise a short,
  /// user-facing description of why it isn't.
  Future<String?> checkAvailability(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      await _js.accountInfo(timeout: timeout);
      return null;
    } catch (e) {
      return describeJetStreamError(e);
    }
  }

  /// List all Object Store buckets visible to the current account, by
  /// listing streams and keeping only the ones backing a bucket
  /// (`OBJ_<bucket>`).
  Future<List<StreamInfo>> listBuckets(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final streams = await _js.listStreams(timeout: timeout);
    return streams
        .where((s) => s.config.name.startsWith(objectStoreStreamPrefix))
        .toList();
  }

  /// Create a new Object Store bucket.
  Future<void> createBucket(
    String bucket, {
    String storage = 'file',
    int replicas = 1,
    int maxBytes = -1,
    Duration? ttl,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _js.createObjectStore(ObjectStoreConfig(
      bucket: bucket,
      storage: storage,
      replicas: replicas,
      maxBytes: maxBytes,
      ttl: (ttl != null && ttl > Duration.zero) ? ttl : Duration.zero,
    ));
  }

  /// Permanently delete a bucket and all of its objects.
  Future<bool> deleteBucket(String bucket,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.deleteObjectStore(bucket, timeout: timeout);
  }

  ObjectStore objectStore(String bucket) => ObjectStore(client, bucket);

  /// List the active (non-tombstoned) objects in [bucket]. Snapshot-only —
  /// unlike `KeyValue`, `ObjectStore` has no `watch()` equivalent in the
  /// vendored 1.1.1 package, so this needs an explicit call to refresh
  /// rather than a live subscription.
  Future<List<ObjectInfo>> listObjects(String bucket) {
    return objectStore(bucket).list();
  }

  /// Upload [data] under [name], overwriting whatever is there.
  Future<ObjectInfo> putObject(String bucket, String name, Uint8List data) {
    return objectStore(bucket).put(name, data);
  }

  /// Download the full byte payload of [name], or `null` if it doesn't
  /// exist. Throws a [NatsException] if the reassembled payload fails its
  /// SHA-256 digest check.
  Future<Uint8List?> getObject(String bucket, String name) {
    return objectStore(bucket).getBytes(name);
  }

  /// Delete [name] (tombstones its metadata and purges its chunks).
  Future<bool> deleteObject(String bucket, String name) {
    return objectStore(bucket).delete(name);
  }
}

/// Strips the `OBJ_` stream-name prefix off, returning the bucket name a
/// user would recognize. Pure function, unit tested independently.
String bucketNameFromObjectStream(String streamName) {
  return streamName.startsWith(objectStoreStreamPrefix)
      ? streamName.substring(objectStoreStreamPrefix.length)
      : streamName;
}

/// Turns an error raised by an Object Store API call into a short,
/// user-facing message. Pure function (no I/O), so it can be unit tested
/// directly without a live server.
String describeObjectStoreError(Object error) {
  if (error is NatsException) {
    final message = error.message ?? '';
    final lower = message.toLowerCase();
    if (lower.contains('digest verification failed')) {
      return 'Download failed integrity verification (digest mismatch) — try again.';
    }
    return describeJetStreamError(error);
  }
  return describeJetStreamError(error);
}
