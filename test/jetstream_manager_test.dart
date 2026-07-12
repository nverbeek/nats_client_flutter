import 'dart:async';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/jetstream_manager.dart';

void main() {
  group('formatBytes', () {
    test('formats zero and negative as 0 B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
    });

    test('formats bytes below 1 KB with no decimal', () {
      expect(formatBytes(512), '512 B');
    });

    test('formats kilobytes with one decimal place', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('formats megabytes and gigabytes', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  group('formatRelativeTime', () {
    test('returns unknown for empty or unparseable input', () {
      expect(formatRelativeTime(''), 'unknown');
      expect(formatRelativeTime('not-a-timestamp'), 'unknown');
    });

    test('returns just now for a timestamp in the last second', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final ts =
          now.subtract(const Duration(milliseconds: 200)).toIso8601String();
      expect(formatRelativeTime(ts, now: now), 'just now');
    });

    test('formats seconds, minutes, hours and days ago', () {
      final now = DateTime.utc(2026, 1, 2, 0, 0, 0);
      expect(
        formatRelativeTime(
            now.subtract(const Duration(seconds: 30)).toIso8601String(),
            now: now),
        '30s ago',
      );
      expect(
        formatRelativeTime(
            now.subtract(const Duration(minutes: 5)).toIso8601String(),
            now: now),
        '5m ago',
      );
      expect(
        formatRelativeTime(
            now.subtract(const Duration(hours: 3)).toIso8601String(),
            now: now),
        '3h ago',
      );
      expect(
        formatRelativeTime(
            now.subtract(const Duration(days: 2)).toIso8601String(),
            now: now),
        '2d ago',
      );
    });
  });

  group('describeJetStreamError', () {
    test('recognizes JetStream-not-enabled style NatsExceptions', () {
      final message = describeJetStreamError(
          NatsException('jetstream not enabled for account'));
      expect(
          message, 'This server or account does not have JetStream enabled.');
    });

    test('treats a NatsException with no message as JetStream unavailable', () {
      final message = describeJetStreamError(NatsException(null));
      expect(
          message, 'This server or account does not have JetStream enabled.');
    });

    test('surfaces other NatsExceptions with their message', () {
      final message = describeJetStreamError(NatsException('stream not found'));
      expect(message, 'JetStream request failed: stream not found');
    });

    test('gives a friendly message for timeouts', () {
      final message = describeJetStreamError(TimeoutException('timed out'));
      expect(message, 'Timed out waiting for a response from the server.');
    });

    test('falls back to a generic message for unexpected errors', () {
      final message = describeJetStreamError(Exception('boom'));
      expect(message, contains('JetStream is unavailable'));
    });
  });
}
