import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:dart_nats/dart_nats.dart' as nats show Consumer;

/// Thin, testable wrapper around a connected [Client] for JetStream
/// monitoring and management operations.
class JetStreamManager {
  final Client client;

  JetStreamManager(this.client);

  JetStream get _js => client.jetStream();

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
      {Duration timeout = const Duration(seconds: 5)}) {
    return _js.publishString(subject, data, timeout: timeout);
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
      await _js.accountInfo(timeout: timeout);
      return null;
    } catch (e) {
      return describeJetStreamError(e);
    }
  }
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
