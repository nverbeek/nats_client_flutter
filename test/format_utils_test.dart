import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/format_utils.dart';

void main() {
  group('decodeMessageTextFor', () {
    test('decodes a message payload as text', () {
      final message = Message<dynamic>(
        'orders.new',
        1,
        Uint8List.fromList('hello'.codeUnits),
        Client(),
      );

      expect(decodeMessageTextFor(message), 'hello');
    });

    test('caches the decoded text per message identity', () {
      final message = Message<dynamic>(
        'orders.new',
        1,
        Uint8List.fromList('hello'.codeUnits),
        Client(),
      );

      final first = decodeMessageTextFor(message);
      // Mutate the underlying bytes after the first decode -- if the second
      // call actually re-decoded instead of hitting the cache, it would see
      // this mutation and return something other than the cached value.
      message.byte.setAll(0, 'HELLO'.codeUnits);
      final second = decodeMessageTextFor(message);

      expect(second, same(first));
    });

    test('two distinct messages with the same bytes decode independently',
        () {
      final a = Message<dynamic>(
        'a', 1, Uint8List.fromList('same'.codeUnits), Client());
      final b = Message<dynamic>(
        'b', 2, Uint8List.fromList('same'.codeUnits), Client());

      expect(decodeMessageTextFor(a), 'same');
      expect(decodeMessageTextFor(b), 'same');
    });
  });


  group('formatCompactCount', () {
    test('renders small counts verbatim', () {
      expect(formatCompactCount(0), '0');
      expect(formatCompactCount(1), '1');
      expect(formatCompactCount(999), '999');
    });

    test('renders thousands with at most one decimal, dropping .0', () {
      expect(formatCompactCount(1000), '1k');
      expect(formatCompactCount(1050), '1.1k');
      expect(formatCompactCount(1100), '1.1k');
      expect(formatCompactCount(9999), '10k');
    });

    test('renders 10k+ with no decimal', () {
      expect(formatCompactCount(12345), '12k');
      expect(formatCompactCount(99999), '100k');
      expect(formatCompactCount(500000), '500k');
    });
  });

  group('formatGroupedCount', () {
    test('leaves small counts ungrouped', () {
      expect(formatGroupedCount(0), '0');
      expect(formatGroupedCount(42), '42');
      expect(formatGroupedCount(999), '999');
    });

    test('groups thousands with commas', () {
      expect(formatGroupedCount(1000), '1,000');
      expect(formatGroupedCount(4210), '4,210');
      expect(formatGroupedCount(999999), '999,999');
      expect(formatGroupedCount(1234567), '1,234,567');
    });
  });

  group('formatTimeOfDay', () {
    test('pads hours, minutes, seconds, and millis, with an AM/PM suffix',
        () {
      expect(formatTimeOfDay(DateTime(2026, 1, 1, 1, 2, 3, 4)),
          '01:02:03.004 AM');
    });

    test('renders midnight and noon as 12, not 0', () {
      expect(
          formatTimeOfDay(DateTime(2026, 1, 1, 0, 0, 0)), '12:00:00.000 AM');
      expect(
          formatTimeOfDay(DateTime(2026, 1, 1, 12, 0, 0)), '12:00:00.000 PM');
    });

    test('renders the last second of the day as 11:59:59.999 PM', () {
      expect(formatTimeOfDay(DateTime(2026, 1, 1, 23, 59, 59, 999)),
          '11:59:59.999 PM');
    });

    test('renders an afternoon hour in 12-hour form', () {
      expect(
          formatTimeOfDay(DateTime(2026, 1, 1, 14, 7, 9)), '02:07:09.000 PM');
    });
  });

  group('formatFullTimestamp', () {
    test('renders a full date and time with milliseconds and AM/PM', () {
      expect(
        formatFullTimestamp(DateTime(2026, 3, 5, 14, 7, 9, 42)),
        '2026-03-05 02:07:09.042 PM',
      );
    });

    test('pads single-digit month/day and zero milliseconds', () {
      expect(
        formatFullTimestamp(DateTime(2026, 1, 2, 0, 0, 0, 0)),
        '2026-01-02 12:00:00.000 AM',
      );
    });
  });

  group('truncatedErrorDetail', () {
    test('leaves short error text untouched', () {
      expect(truncatedErrorDetail(Exception('boom')), 'Exception: boom');
    });

    test('truncates long error text and appends an ellipsis', () {
      final longError = Exception('x' * 200);
      final result = truncatedErrorDetail(longError, maxLength: 20);
      expect(result.length, 21); // 20 chars + ellipsis
      expect(result.endsWith('…'), isTrue);
    });
  });

  group('formatEstimatedDuration', () {
    test('shows <1s for a duration that rounds down to nothing', () {
      expect(formatEstimatedDuration(Duration.zero), '<1s');
    });

    test('shows exact milliseconds under a second', () {
      expect(formatEstimatedDuration(const Duration(milliseconds: 450)),
          '~450ms');
    });

    test('shows seconds only when under a minute', () {
      expect(formatEstimatedDuration(const Duration(seconds: 45)), '~45s');
    });

    test('shows minutes and seconds for a minute or more', () {
      expect(
          formatEstimatedDuration(
              const Duration(minutes: 2, seconds: 15)),
          '~2m 15s');
    });
  });
}
