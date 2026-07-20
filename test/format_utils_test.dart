import 'dart:convert';
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

    test('two distinct messages with the same bytes decode independently', () {
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
    test('pads hours, minutes, seconds, and millis, with an AM/PM suffix', () {
      expect(
          formatTimeOfDay(DateTime(2026, 1, 1, 1, 2, 3, 4)), '01:02:03.004 AM');
    });

    test('renders midnight and noon as 12, not 0', () {
      expect(formatTimeOfDay(DateTime(2026, 1, 1, 0, 0, 0)), '12:00:00.000 AM');
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

  group('describePublishError', () {
    test('names the reconnect-buffer-full case distinctly', () {
      final error = NatsException('reconnect buffer full');
      expect(describePublishError(error),
          'Too many messages queued while disconnected — this one was not sent.');
    });

    test('is case-insensitive when matching the buffer-full message', () {
      final error = NatsException('Reconnect Buffer Full');
      expect(describePublishError(error), contains('Too many messages queued'));
    });

    test('falls back to a truncated generic message for anything else', () {
      final error = NatsException('request error: client not connected');
      expect(describePublishError(error),
          'Failed to send: NatsException: request error: client not connected');
    });

    test('handles a non-NatsException error the same generic way', () {
      final error = Exception('socket closed');
      expect(describePublishError(error),
          'Failed to send: Exception: socket closed');
    });
  });

  group('isValidNatsName', () {
    test('accepts a plain identifier', () {
      expect(isValidNatsName('orders-processor'), isTrue);
      expect(isValidNatsName('ORDERS_2'), isTrue);
    });

    test('rejects empty, dots, wildcards, and whitespace', () {
      expect(isValidNatsName(''), isFalse);
      expect(isValidNatsName('orders.processor'), isFalse);
      expect(isValidNatsName('orders*'), isFalse);
      expect(isValidNatsName('orders>'), isFalse);
      expect(isValidNatsName('orders processor'), isFalse);
      expect(isValidNatsName('orders\tprocessor'), isFalse);
    });
  });

  group('isValidNatsSubjectFilter', () {
    test('accepts literal and wildcard subjects', () {
      expect(isValidNatsSubjectFilter('orders.new'), isTrue);
      expect(isValidNatsSubjectFilter('orders.*'), isTrue);
      expect(isValidNatsSubjectFilter('orders.>'), isTrue);
      expect(isValidNatsSubjectFilter('*'), isTrue);
      expect(isValidNatsSubjectFilter('>'), isTrue);
    });

    test('rejects empty segments (leading/trailing/double dots)', () {
      expect(isValidNatsSubjectFilter(''), isFalse);
      expect(isValidNatsSubjectFilter('.orders'), isFalse);
      expect(isValidNatsSubjectFilter('orders.'), isFalse);
      expect(isValidNatsSubjectFilter('orders..new'), isFalse);
    });

    test('rejects whitespace', () {
      expect(isValidNatsSubjectFilter('orders new'), isFalse);
    });

    test('rejects a partial wildcard within a token', () {
      expect(isValidNatsSubjectFilter('ord*rs'), isFalse);
      expect(isValidNatsSubjectFilter('orders.new>'), isFalse);
    });

    test('rejects > anywhere but the final token', () {
      expect(isValidNatsSubjectFilter('orders.>.new'), isFalse);
    });
  });

  group('isValidLiteralNatsSubject', () {
    test('accepts a literal subject', () {
      expect(isValidLiteralNatsSubject('orders.new'), isTrue);
    });

    test('rejects wildcards even though they are valid filter syntax', () {
      expect(isValidLiteralNatsSubject('orders.*'), isFalse);
      expect(isValidLiteralNatsSubject('orders.>'), isFalse);
      expect(isValidLiteralNatsSubject('*'), isFalse);
      expect(isValidLiteralNatsSubject('>'), isFalse);
    });

    test('rejects empty segments and whitespace like the filter check does',
        () {
      expect(isValidLiteralNatsSubject(''), isFalse);
      expect(isValidLiteralNatsSubject('orders..new'), isFalse);
      expect(isValidLiteralNatsSubject('orders new'), isFalse);
    });
  });

  group('isValidUtf8', () {
    test('accepts plain ASCII and multi-byte UTF-8', () {
      expect(isValidUtf8(Uint8List.fromList('hello'.codeUnits)), isTrue);
      expect(isValidUtf8(Uint8List.fromList(utf8.encode('héllo 🎉'))), isTrue);
    });

    test('accepts an empty payload', () {
      expect(isValidUtf8(Uint8List(0)), isTrue);
    });

    test('rejects an invalid byte sequence', () {
      expect(
          isValidUtf8(Uint8List.fromList([0xFF, 0xFE, 0x00, 0x01])), isFalse);
    });

    test('rejects a truncated multi-byte sequence', () {
      // 0xC3 alone starts a 2-byte UTF-8 sequence with no continuation byte.
      expect(isValidUtf8(Uint8List.fromList([0xC3])), isFalse);
    });
  });

  group('formatHexDump', () {
    test('renders a short payload as one row with offset/hex/ascii', () {
      final dump = formatHexDump(Uint8List.fromList('Hi!'.codeUnits));
      expect(dump, startsWith('00000000'));
      expect(dump, contains('48 69 21'));
      expect(dump, endsWith('Hi!'));
    });

    test('renders non-printable bytes as dots in the ASCII column', () {
      final dump = formatHexDump(Uint8List.fromList([0x00, 0xFF, 0x41]));
      expect(dump, contains('00 ff 41'));
      expect(dump, endsWith('..A'));
    });

    test('wraps to a second row past bytesPerRow bytes', () {
      final bytes = Uint8List.fromList(List.generate(17, (i) => i));
      final dump = formatHexDump(bytes, bytesPerRow: 16);
      final lines = dump.split('\n');
      expect(lines, hasLength(2));
      expect(lines[1], startsWith('00000010'));
    });

    test('handles an empty payload as an empty string', () {
      expect(formatHexDump(Uint8List(0)), isEmpty);
    });

    test('caps output at the byte limit and says how much was omitted', () {
      final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final dump = formatHexDump(bytes, limit: 128);

      // 128 bytes at 16/row = 8 rows, plus the blank line and the notice.
      final rows =
          dump.split('\n').where((l) => l.startsWith('000000')).toList();
      expect(rows, hasLength(8));
      expect(dump, contains('truncated'));
      expect(dump, contains('first 128 of 300 bytes'));
      expect(dump, contains('172 not shown'));
      // Nothing past the limit leaked into the dump: byte 128 would start a
      // 9th row at offset 00000080.
      expect(dump, isNot(contains('00000080')));
    });

    test('adds no truncation notice when the payload fits the limit', () {
      final bytes = Uint8List.fromList(List.generate(128, (i) => i % 256));
      expect(formatHexDump(bytes, limit: 128), isNot(contains('truncated')));
    });

    test('defaults to a limit that keeps a 1MB payload from being dumped whole',
        () {
      // Regression guard for the UI freeze: an uncapped dump of a 1MB
      // payload builds a ~4.3MB string and ~65k lines in one frame.
      final bytes = Uint8List(1024 * 1024);
      final dump = formatHexDump(bytes);
      expect(dump, contains('truncated'));
      expect(dump.length, lessThan(400 * 1024));
    });
  });

  group('formatConfiguredDuration', () {
    test('shows seconds only when under a minute', () {
      expect(formatConfiguredDuration(const Duration(seconds: 45)), '45s');
    });

    test('carries the seconds remainder rather than truncating to minutes', () {
      // The bug this replaced rendered both of these as "1m", making two
      // materially different ack-wait settings look identical.
      expect(formatConfiguredDuration(const Duration(seconds: 90)), '1m 30s');
      expect(formatConfiguredDuration(const Duration(seconds: 60)), '1m');
    });

    test('carries the minutes remainder into hours', () {
      expect(formatConfiguredDuration(const Duration(minutes: 135)), '2h 15m');
      expect(formatConfiguredDuration(const Duration(hours: 2)), '2h');
    });

    test('grows a days tier past 24 hours instead of a huge hour count', () {
      expect(formatConfiguredDuration(const Duration(hours: 25)), '1d 1h');
      expect(formatConfiguredDuration(const Duration(days: 3)), '3d');
    });

    test('clamps a negative duration rather than rendering a negative unit',
        () {
      expect(formatConfiguredDuration(const Duration(seconds: -5)), '0s');
    });
  });

  group('formatEstimatedDuration', () {
    test('shows <1s for a duration that rounds down to nothing', () {
      expect(formatEstimatedDuration(Duration.zero), '<1s');
    });

    test('shows exact milliseconds under a second', () {
      expect(
          formatEstimatedDuration(const Duration(milliseconds: 450)), '~450ms');
    });

    test('shows seconds only when under a minute', () {
      expect(formatEstimatedDuration(const Duration(seconds: 45)), '~45s');
    });

    test('shows minutes and seconds for a minute or more', () {
      expect(formatEstimatedDuration(const Duration(minutes: 2, seconds: 15)),
          '~2m 15s');
    });
  });
}
