import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:dart_nats/dart_nats.dart' as nats show Consumer;

/// Thin, testable wrapper around a connected [Client] for JetStream
/// monitoring and management operations.
class JetStreamManager {
  final Client client;

  JetStreamManager(this.client);

  JetStream get _js => client.jetStream();

  /// The most recently fetched account usage/limits snapshot, populated as a
  /// side effect of [checkAvailability] (which already fetches it on every
  /// dashboard load to probe JetStream availability). `null` until the first
  /// successful [checkAvailability] or [fetchAccountInfo] call.
  AccountInfo? lastAccountInfo;

  /// List all JetStream streams visible to the current account.
  Future<List<StreamInfo>> listStreams(
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.listStreams(timeout: timeout);
  }

  /// List all consumers bound to [streamName].
  Future<List<ConsumerInfo>> listConsumers(String streamName,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.listConsumers(streamName, timeout: timeout);
  }

  /// Get up-to-date info for a single stream.
  Future<StreamInfo> streamInfo(String streamName,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.streamInfo(streamName, timeout: timeout);
  }

  /// Get up-to-date info for a single consumer.
  Future<ConsumerInfo> consumerInfo(String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.consumerInfo(streamName, consumerName, timeout: timeout);
  }

  /// Get up-to-date info for a single consumer, plus a handful of
  /// `ConsumerConfig` fields `dart_nats` 1.2.3's `ConsumerInfo.fromJson`
  /// doesn't parse even though the server always sends them (`ack_wait`,
  /// `max_deliver`, `max_ack_pending`). Issues the same raw
  /// `$JS.API.CONSUMER.INFO.<stream>.<consumer>` request `consumerInfo()`
  /// makes internally, reusing `ConsumerInfo.fromJson` for everything it
  /// already handles and reading the three missing fields off the same JSON
  /// itself -- mirroring the raw-JSON bypass `KvManager.bucketStatus` uses
  /// for the same kind of package-side parsing gap.
  Future<ConsumerDetail> consumerDetail(
      String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final subject = '\$JS.API.CONSUMER.INFO.$streamName.$consumerName';
    final response =
        await client.request(subject, Uint8List(0), timeout: timeout);
    final map = jsonDecode(response.string) as Map<String, dynamic>;
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    final info = ConsumerInfo.fromJson(map);
    final config = map['config'] as Map<String, dynamic>? ?? {};
    final ackWaitNanos = config['ack_wait'] as int?;
    return ConsumerDetail(
      info: info,
      ackWait: (ackWaitNanos != null && ackWaitNanos > 0)
          ? Duration(microseconds: ackWaitNanos ~/ 1000)
          : null,
      maxDeliver: config['max_deliver'] as int?,
      maxAckPending: config['max_ack_pending'] as int?,
    );
  }

  /// Starts an ephemeral, auto-cleaning ordered consumer for browsing a
  /// stream's messages, without requiring the user to manage consumer
  /// lifecycle themselves. Caller is responsible for calling `.stop()` on
  /// the returned [OrderedConsumer] when the browse panel closes.
  OrderedConsumer browseStream(String streamName) {
    return _js.orderedConsumer(streamName, OrderedConsumerConfig());
  }

  /// Create a new stream from [config].
  Future<void> createStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.createStream(config, timeout: timeout);
  }

  /// Update an existing stream to [config]. The server treats this as a full
  /// replacement of the stream's configuration (not a partial merge), so
  /// [config] should normally originate from [streamDetail] (or the Edit
  /// dialog pre-filled from it) rather than a hand-built partial config.
  Future<void> updateStream(StreamConfig config,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.updateStream(config, timeout: timeout);
  }

  /// Get up-to-date info for a single stream, plus a handful of
  /// `StreamConfig` fields `dart_nats` 1.2.3's `StreamInfo.fromJson` doesn't
  /// parse even though the server always sends them (`max_age`,
  /// `num_replicas`, `discard`, `allow_rollup_hdrs`, `deny_delete`,
  /// `deny_purge`, `max_msgs_per_subject`, `max_msg_size`, `allow_direct`).
  /// Issues the same raw `$JS.API.STREAM.INFO.<stream>` request
  /// [streamInfo] makes internally, reusing `StreamInfo.fromJson` for
  /// everything it already handles and reading the missing fields off the
  /// same JSON itself -- mirroring the raw-JSON bypass [consumerDetail] uses
  /// for the same kind of package-side parsing gap. The returned
  /// `StreamInfo.config` is a fully-populated `StreamConfig`, suitable for
  /// pre-filling the Edit Stream dialog.
  Future<StreamInfo> streamDetail(String streamName,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final subject = '\$JS.API.STREAM.INFO.$streamName';
    final response =
        await client.request(subject, Uint8List(0), timeout: timeout);
    final map = jsonDecode(response.string) as Map<String, dynamic>;
    if (map['error'] != null) {
      throw NatsException(map['error']['description'] as String);
    }
    final info = StreamInfo.fromJson(map);
    final cfg = map['config'] as Map<String, dynamic>? ?? {};
    final maxAgeNanos = cfg['max_age'] as int?;
    return StreamInfo(
      type: info.type,
      created: info.created,
      state: info.state,
      config: StreamConfig(
        name: info.config.name,
        subjects: info.config.subjects,
        storage: info.config.storage,
        retention: info.config.retention,
        maxMsgs: info.config.maxMsgs,
        maxBytes: info.config.maxBytes,
        allowRollup: cfg['allow_rollup_hdrs'] as bool?,
        denyDelete: cfg['deny_delete'] as bool?,
        denyPurge: cfg['deny_purge'] as bool?,
        discard: cfg['discard'] as String?,
        allowDirect: cfg['allow_direct'] as bool?,
        maxMsgsPerSubject: cfg['max_msgs_per_subject'] as int?,
        maxMsgSize: cfg['max_msg_size'] as int?,
        maxAge: (maxAgeNanos != null && maxAgeNanos > 0)
            ? Duration(microseconds: maxAgeNanos ~/ 1000)
            : null,
        numReplicas: cfg['num_replicas'] as int?,
      ),
    );
  }

  /// Permanently delete a stream and all of its messages.
  Future<void> deleteStream(String streamName,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.deleteStream(streamName, timeout: timeout);
  }

  /// Purge all messages from a stream, keeping the stream itself.
  Future<void> purgeStream(String streamName,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.stream(streamName).purge(timeout: timeout);
  }

  /// Create a new consumer (push or pull, durable or ephemeral) on [streamName].
  Future<void> createConsumer(String streamName, ConsumerConfig config,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.createConsumer(streamName, config, timeout: timeout);
  }

  /// Permanently delete a consumer from a stream.
  Future<void> deleteConsumer(String streamName, String consumerName,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.deleteConsumer(streamName, consumerName, timeout: timeout);
  }

  /// Publish a string payload into JetStream and wait for the server's
  /// acknowledgement (stream name + assigned sequence number).
  Future<PubAck> publish(String subject, String data,
      {Duration timeout = const Duration(seconds: 5), Header? header}) {
    return _js.publishString(subject, data, timeout: timeout, header: header);
  }

  /// Bind to an existing named consumer to tail its deliveries. Unlike
  /// [browseStream], the returned handle preserves whatever ack policy the
  /// consumer was created with, so explicit-ack consumers can actually be
  /// acked/nak'd/terminated via the delivered [Message]s.
  nats.Consumer<dynamic> tailConsumer(String streamName, String consumerName) {
    return _js.consumer(streamName, consumerName);
  }

  /// Returns `null` if JetStream is available on the current account,
  /// otherwise a short, user-facing description of why it isn't.
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
  /// [lastAccountInfo]. Unlike [checkAvailability], this surfaces the server
  /// error rather than turning it into a `String?` description, so callers
  /// (e.g. the Account Info dialog's manual refresh) can format it themselves.
  Future<AccountInfo> fetchAccountInfo(
      {Duration timeout = const Duration(seconds: 3)}) async {
    final info = await _js.accountInfo(timeout: timeout);
    lastAccountInfo = info;
    return info;
  }
}

/// A consumer's standard `ConsumerInfo` plus the ack-wait/max-deliver/
/// max-ack-pending config fields `dart_nats` doesn't parse on its own -- see
/// [JetStreamManager.consumerDetail].
class ConsumerDetail {
  final ConsumerInfo info;
  final Duration? ackWait;
  final int? maxDeliver;
  final int? maxAckPending;

  ConsumerDetail({
    required this.info,
    required this.ackWait,
    required this.maxDeliver,
    required this.maxAckPending,
  });
}

/// Turns an error raised by a JetStream API call into a short, user-facing
/// message. Pure function (no I/O), so it can be unit tested directly
/// without a live server.
String describeJetStreamError(Object error) {
  if (error is NatsException) {
    final message = error.message ?? '';
    final lower = message.toLowerCase();
    if (lower.contains('jetstream not enabled') ||
        lower.contains('jetstream not available') ||
        lower.contains('no responders')) {
      return 'This server or account does not have JetStream enabled.';
    }
    if (message.isEmpty) {
      return 'This server or account does not have JetStream enabled.';
    }
    return 'JetStream request failed: $message';
  }
  if (error is TimeoutException) {
    return 'Timed out waiting for a response from the server.';
  }
  return 'JetStream is unavailable: $error';
}

/// Formats a byte count as a short human-readable string, e.g. `1.2 KB`.
/// Pure function, unit tested independently of any network calls.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final formatted =
      unitIndex == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$formatted ${units[unitIndex]}';
}

/// Formats an ISO-8601 timestamp string (as returned by the JetStream API)
/// into a short relative age, e.g. `3m ago`. Falls back to `unknown` if the
/// timestamp is missing or can't be parsed.
String formatRelativeTime(String isoTimestamp, {DateTime? now}) {
  if (isoTimestamp.isEmpty) return 'unknown';
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return 'unknown';

  final reference = now ?? DateTime.now().toUtc();
  final diff = reference.difference(parsed.toUtc());
  if (diff.isNegative || diff.inSeconds < 1) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
