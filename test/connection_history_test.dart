import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/connection_history.dart';

void main() {
  group('ConnectionHistoryEntry', () {
    test('fullUri concatenates scheme, host, and port', () {
      const entry =
          ConnectionHistoryEntry(scheme: 'nats://', host: '127.0.0.1', port: '4222');
      expect(entry.fullUri, 'nats://127.0.0.1:4222');
    });

    test('sameTarget compares scheme, host, and port, not object identity', () {
      const a =
          ConnectionHistoryEntry(scheme: 'nats://', host: '127.0.0.1', port: '4222');
      const b =
          ConnectionHistoryEntry(scheme: 'nats://', host: '127.0.0.1', port: '4222');
      const differentPort =
          ConnectionHistoryEntry(scheme: 'nats://', host: '127.0.0.1', port: '4223');
      const differentHost =
          ConnectionHistoryEntry(scheme: 'nats://', host: '127.0.0.2', port: '4222');
      const differentScheme =
          ConnectionHistoryEntry(scheme: 'ws://', host: '127.0.0.1', port: '4222');

      expect(a.sameTarget(b), isTrue);
      expect(a.sameTarget(differentPort), isFalse);
      expect(a.sameTarget(differentHost), isFalse);
      expect(a.sameTarget(differentScheme), isFalse);
    });
  });

  group('encodeConnectionHistory / decodeConnectionHistory', () {
    test('round-trips scheme, host, and port', () {
      final original = [
        const ConnectionHistoryEntry(
            scheme: 'nats://', host: '127.0.0.1', port: '4222'),
        const ConnectionHistoryEntry(
            scheme: 'ws://', host: 'demo.nats.io', port: '8080'),
      ];

      final decoded = decodeConnectionHistory(encodeConnectionHistory(original));

      expect(decoded.length, 2);
      expect(decoded[0].scheme, 'nats://');
      expect(decoded[0].host, '127.0.0.1');
      expect(decoded[0].port, '4222');
      expect(decoded[1].scheme, 'ws://');
      expect(decoded[1].host, 'demo.nats.io');
      expect(decoded[1].port, '8080');
    });

    test('empty list round-trips to empty list', () {
      expect(decodeConnectionHistory(encodeConnectionHistory([])), isEmpty);
    });

    test('preserves list order', () {
      final original = [
        const ConnectionHistoryEntry(scheme: 'nats://', host: 'a', port: '1'),
        const ConnectionHistoryEntry(scheme: 'nats://', host: 'b', port: '2'),
        const ConnectionHistoryEntry(scheme: 'nats://', host: 'c', port: '3'),
      ];

      final decoded = decodeConnectionHistory(encodeConnectionHistory(original));

      expect(decoded.map((e) => e.host).toList(), ['a', 'b', 'c']);
    });
  });

  group('recordConnection', () {
    const entryA =
        ConnectionHistoryEntry(scheme: 'nats://', host: 'a', port: '4222');
    const entryB =
        ConnectionHistoryEntry(scheme: 'nats://', host: 'b', port: '4222');
    const entryC =
        ConnectionHistoryEntry(scheme: 'nats://', host: 'c', port: '4222');

    test('a brand-new target is inserted at the front', () {
      final result = recordConnection([entryA], 'nats://', 'b', '4222');
      expect(result.map((e) => e.host).toList(), ['b', 'a']);
    });

    test('reconnecting to an existing target moves it to the front instead of duplicating', () {
      final result =
          recordConnection([entryA, entryB, entryC], 'nats://', 'c', '4222');
      expect(result.map((e) => e.host).toList(), ['c', 'a', 'b']);
      expect(result.length, 3);
    });

    test('a different port for the same host is treated as a distinct target', () {
      final result = recordConnection([entryA], 'nats://', 'a', '4223');
      expect(result.length, 2);
      expect(result[0].port, '4223');
      expect(result[1].port, '4222');
    });

    test('a different scheme for the same host/port is treated as a distinct target', () {
      final result = recordConnection([entryA], 'ws://', 'a', '4222');
      expect(result.length, 2);
      expect(result[0].scheme, 'ws://');
      expect(result[1].scheme, 'nats://');
    });

    test('caps at maxConnectionHistory, dropping the oldest', () {
      // host0 = most recent .. host9 = oldest, mirroring the app's own
      // most-recent-first storage order, already sitting right at the cap.
      final full = List.generate(
        maxConnectionHistory,
        (i) => ConnectionHistoryEntry(
            scheme: 'nats://', host: 'host$i', port: '4222'),
      );

      final result = recordConnection(full, 'nats://', 'new-host', '4222');

      expect(result.length, maxConnectionHistory);
      expect(result.first.host, 'new-host');
      // The oldest entry (last in most-recent-first order) fell off the cap.
      expect(
          result.any((e) => e.host == 'host${maxConnectionHistory - 1}'),
          isFalse);
      // The previously most-recent entry survives, just shifted back one.
      expect(result.any((e) => e.host == 'host0'), isTrue);
    });

    test('moving an existing entry to the front does not shrink the list under the cap', () {
      final full = List.generate(
        maxConnectionHistory,
        (i) => ConnectionHistoryEntry(
            scheme: 'nats://', host: 'host$i', port: '4222'),
      );

      // Reconnecting to an entry already in a full history should just
      // reorder it, not grow past the cap or drop an extra entry.
      final result = recordConnection(full, 'nats://', 'host5', '4222');

      expect(result.length, maxConnectionHistory);
      expect(result.first.host, 'host5');
    });

    test('does not mutate the list passed in', () {
      final original = [entryA, entryB];
      recordConnection(original, 'nats://', 'c', '4222');
      expect(original.map((e) => e.host).toList(), ['a', 'b']);
    });
  });
}
