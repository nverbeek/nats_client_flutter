import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;

import 'jetstream_manager.dart'
    show describeJetStreamError, listStreamsPaginated;

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
  ///
  /// Uses [listStreamsPaginated] rather than `JetStream.listStreams()`
  /// directly -- see that function's doc comment for why (a busy shared
  /// account can silently truncate the unpaginated call before it ever
  /// reaches any `KV_`-prefixed streams).
  Future<List<StreamInfo>> listBuckets(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final streams = await listStreamsPaginated(client, timeout: timeout);
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
