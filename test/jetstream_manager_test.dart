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

  group('tierFromJson', () {
    test('reads usage/limits fields from the top level', () {
      final tier = tierFromJson({
        'memory': 1024,
        'storage': 2048,
        'reserved_memory': 4096,
        'reserved_storage': 8192,
        'streams': 3,
        'consumers': 5,
      });
      expect(tier.memory, 1024);
      expect(tier.storage, 2048);
      expect(tier.reservedMemory, 4096);
      expect(tier.reservedStorage, 8192);
      expect(tier.streams, 3);
      expect(tier.consumers, 5);
    });

    test('defaults missing fields to zero', () {
      final tier = tierFromJson({});
      expect(tier.memory, 0);
      expect(tier.storage, 0);
      expect(tier.reservedMemory, 0);
      expect(tier.reservedStorage, 0);
      expect(tier.streams, 0);
      expect(tier.consumers, 0);
    });

    test(
        'does not throw on a huge double sentinel (a real server\'s uint64 '
        '"-1 unlimited" for reserved_storage, observed to round-trip through '
        'JSON as 18446744073709552000.0)', () {
      final tier = tierFromJson({'reserved_storage': 18446744073709552000.0});
      expect(tier.reservedStorage, greaterThan(0));
    });
  });

  group('accountInfoFromJson', () {
    test('parses a real single-tier \$JS.API.INFO response '
        '(usage fields at the top level, no "tier" key)', () {
      // Captured verbatim from a live `nats:latest -js` server's
      // `\$JS.API.INFO` response after creating one stream.
      final json = {
        'type': 'io.nats.jetstream.api.v1.account_info_response',
        'memory': 0,
        'storage': 0,
        'reserved_memory': 0,
        'reserved_storage': 18446744073709552000.0,
        'streams': 1,
        'consumers': 0,
        'limits': {
          'max_memory': -1,
          'max_storage': -1,
          'max_streams': -1,
          'max_consumers': -1,
        },
        'api': {'level': 1, 'total': 8, 'errors': 0},
      };

      final info = accountInfoFromJson(json);

      expect(info.tier.streams, 1);
      expect(info.tier.consumers, 0);
      expect(info.api.total, 8);
      expect(info.api.level, 1);
      expect(info.domain, '');
      expect(info.tiers, isEmpty);
    });

    test('parses multi-tier accounts into the tiers map', () {
      final json = {
        'streams': 2,
        'api': {'total': 1},
        'tiers': {
          'R1': {'streams': 2, 'memory': 100},
          'R3': {'streams': 0, 'memory': 0},
        },
      };

      final info = accountInfoFromJson(json);

      expect(info.tiers.keys, containsAll(['R1', 'R3']));
      expect(info.tiers['R1']!.streams, 2);
      expect(info.tiers['R1']!.memory, 100);
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
