import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;

import 'jetstream_manager.dart' show describeJetStreamError, jsApiRequest;

/// Prefix JetStream uses for the backing stream of every KV bucket. Bucket
/// names shown in the UI have this stripped back off.
const String kvStreamPrefix = 'KV_';

/// Thin, testable wrapper around a connected [Client] for Key-Value bucket
/// monitoring and management, mirroring the shape of `JetStreamManager`.
class KvManager {
  final Client client;

  KvManager(this.client);

  JetStream get _js => client.jetStream();

  /// The most recently fetched account usage/limits snapshot, populated as a
  /// side effect of [checkAvailability] (which already fetches it on every
  /// dashboard load to probe JetStream/KV availability). `null` until the
  /// first successful [checkAvailability] or [fetchAccountInfo] call.
  AccountInfo? lastAccountInfo;

  /// Returns `null` if JetStream (and therefore KV, which is built on top of
  /// it) is available on the current account, otherwise a short, user-facing
  /// description of why it isn't.
  Future<String?> checkAvailability(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      lastAccountInfo = await _js.accountInfo(timeout: timeout);
      return null;
    } catch (e) {
      return describeJetStreamError(e);
    }
  }

  /// Fetches a fresh account usage/limits snapshot from the server, updating
  /// [lastAccountInfo]. See `JetStreamManager.fetchAccountInfo` for why this
  /// is separate from [checkAvailability].
  Future<AccountInfo> fetchAccountInfo(
      {Duration timeout = const Duration(seconds: 3)}) async {
    final info = await _js.accountInfo(timeout: timeout);
    lastAccountInfo = info;
    return info;
  }

  /// List all KV buckets visible to the current account, by listing streams
  /// and keeping only the ones backing a KV bucket (`KV_<bucket>`).
  Future<List<StreamInfo>> listBuckets(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final streams = await _js.listStreams(timeout: timeout);
    return streams.where((s) => s.config.name.startsWith(kvStreamPrefix))
        .toList();
  }

  /// Create a new KV bucket. Built as a raw [StreamConfig] rather than going
  /// through `KeyValueConfig.toStreamConfig()` — the vendored 1.1.1 package's
  /// version of that conversion silently drops both `ttl` and replica count,
  /// so a bucket created via the package's own `createKeyValue()` helper
  /// can't actually get either of those settings onto the wire.
  Future<void> createBucket(
    String bucket, {
    int history = 1,
    Duration? ttl,
    int replicas = 1,
    String storage = 'file',
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _js.createStream(
      StreamConfig(
        name: '$kvStreamPrefix$bucket',
        subjects: ['\$KV.$bucket.>'],
        storage: storage,
        maxMsgs: -1,
        allowRollup: true,
        discard: 'new',
        allowDirect: true,
        denyDelete: true,
        maxMsgsPerSubject: history,
        maxAge: (ttl != null && ttl > Duration.zero) ? ttl : null,
        numReplicas: replicas,
      ),
      timeout: timeout,
    );
  }

  /// Permanently delete a bucket and all of its keys.
  Future<void> deleteBucket(String bucket,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.deleteKeyValue(bucket, timeout: timeout);
  }

  KeyValue keyValue(String bucket) => KeyValue(client, bucket);

  /// List the active (non-tombstoned) keys in [bucket].
  Future<List<String>> listKeys(String bucket,
      {Duration timeout = const Duration(seconds: 5)}) {
    return keyValue(bucket).keys(timeout: timeout);
  }

  /// Fetch the current entry (value + revision) for [key], or `null` if it
  /// doesn't exist or has been deleted/purged.
  Future<KeyValueEntry?> getEntry(String bucket, String key) {
    return keyValue(bucket).get(key);
  }

  /// Put a new value under [key], overwriting whatever is there.
  Future<int> putValue(String bucket, String key, String value) {
    return keyValue(bucket).putString(key, value);
  }

  /// Update [key]'s value only if its current revision is still
  /// [expectedRevision] — an optimistic-concurrency check. Throws a
  /// [NatsException] (wrapping the server's "wrong last sequence" error) if
  /// the key has changed since [expectedRevision] was read.
  Future<int> updateValue(
      String bucket, String key, String value, int expectedRevision) {
    return keyValue(bucket).updateString(key, value, expectedRevision);
  }

  /// Delete [key] (adds a deletion tombstone; history is kept).
  Future<bool> deleteKey(String bucket, String key) {
    return keyValue(bucket).delete(key);
  }

  /// Purge [key] (removes all historical revisions).
  Future<bool> purgeKey(String bucket, String key) {
    return keyValue(bucket).purge(key);
  }

  /// Get the full revision history for [key], oldest first.
  Future<List<KeyValueEntry>> keyHistory(String bucket, String key,
      {Duration timeout = const Duration(seconds: 5)}) {
    return keyValue(bucket).history(key, timeout: timeout).toList();
  }

  /// Live stream of put/delete/purge operations across every key in
  /// [bucket], starting from whatever happens next (no back-catalog replay).
  Stream<KeyValueEntry?> watch(String bucket) {
    return keyValue(bucket).watch();
  }

  /// Fetches a fuller status snapshot for [bucket] than `dart_nats`
  /// 1.2.3's `KeyValue.status()` exposes -- that method (and the
  /// `StreamConfig.fromJson` it relies on) never parses `max_age` (TTL) or
  /// `num_replicas` even though the server always sends them on
  /// `$JS.API.STREAM.INFO`. This issues that same raw request itself and
  /// reads the two missing fields off the JSON directly, mirroring the
  /// raw-`StreamConfig` bypass [createBucket] already uses for the same kind
  /// of package-side parsing gap.
  Future<KvBucketStatus> bucketStatus(String bucket,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final streamName = '$kvStreamPrefix$bucket';
    final subject = '\$JS.API.STREAM.INFO.$streamName';
    final map = await jsApiRequest(client, subject, timeout: timeout);
    final config = map['config'] as Map<String, dynamic>? ?? {};
    final state = map['state'] as Map<String, dynamic>? ?? {};
    final maxAgeNanos = config['max_age'] as int? ?? 0;
    return KvBucketStatus(
      bucket: bucket,
      history: config['max_msgs_per_subject'] as int? ?? 1,
      storage: config['storage'] as String? ?? 'file',
      size: state['bytes'] as int? ?? 0,
      values: state['messages'] as int? ?? 0,
      ttl: maxAgeNanos > 0
          ? Duration(microseconds: maxAgeNanos ~/ 1000)
          : null,
      replicas: config['num_replicas'] as int? ?? 1,
      lastSeq: state['last_seq'] as int? ?? 0,
    );
  }
}

/// A KV bucket's history depth, storage type, live size/count, and (unlike
/// `dart_nats`'s own `KeyValueStatus`) TTL and replica count -- see
/// [KvManager.bucketStatus].
class KvBucketStatus {
  final String bucket;
  final int history;
  final String storage;
  final int size;
  final int values;
  final Duration? ttl;
  final int replicas;

  /// Sequence number of the last message in the backing stream -- i.e. the
  /// revision of the most recent put/delete/purge in this bucket, since KV
  /// revisions *are* stream sequences. Not displayed anywhere; it exists so
  /// `KvDashboard` can tell in one request whether anything changed while
  /// disconnected instead of re-fetching every key. Defaults to `0`
  /// ("nothing written"), which reads as "can't rule out a change" and so
  /// degrades safely toward re-fetching.
  final int lastSeq;

  KvBucketStatus({
    required this.bucket,
    required this.history,
    required this.storage,
    required this.size,
    required this.values,
    required this.ttl,
    required this.replicas,
    this.lastSeq = 0,
  });
}

/// Strips the `KV_` stream-name prefix off, returning the bucket name a
/// user would recognize. Pure function, unit tested independently.
String bucketNameFromStream(String streamName) {
  return streamName.startsWith(kvStreamPrefix)
      ? streamName.substring(kvStreamPrefix.length)
      : streamName;
}

/// Turns an error raised by a KV API call into a short, user-facing message.
/// Pure function (no I/O), so it can be unit tested directly without a live
/// server.
String describeKvError(Object error) {
  if (error is NatsException) {
    final message = error.message ?? '';
    final lower = message.toLowerCase();
    if (lower.contains('wrong last sequence')) {
      return 'This key changed since it was loaded — reload and try again.';
    }
    if (lower.contains('key already exists')) {
      return 'That key already exists.';
    }
    return describeJetStreamError(error);
  }
  return describeJetStreamError(error);
}
