import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/service_discovery_manager.dart';

void main() {
  group('describeServiceDiscoveryError', () {
    test('uses a NatsException\'s own message', () {
      final message = describeServiceDiscoveryError(
          NatsException('request error: client not connected'));
      expect(message, 'request error: client not connected');
    });

    test('falls back to a generic message for a NatsException with no message',
        () {
      final message = describeServiceDiscoveryError(NatsException(null));
      expect(message, 'Service discovery failed.');
    });

    test('falls back to toString() for other errors', () {
      final message = describeServiceDiscoveryError(Exception('boom'));
      expect(message, contains('boom'));
    });
  });

  group('formatNanos', () {
    test('formats zero and negative durations as 0 ms', () {
      expect(formatNanos(0), '0 ms');
      expect(formatNanos(-5), '0 ms');
    });

    test('formats sub-microsecond durations in nanoseconds', () {
      expect(formatNanos(500), '500 ns');
    });

    test('formats sub-millisecond durations in microseconds', () {
      expect(formatNanos(1500), '1.5 µs');
    });

    test('formats sub-second durations in milliseconds', () {
      expect(formatNanos(2500000), '2.5 ms');
    });

    test('formats second-plus durations in seconds', () {
      expect(formatNanos(1500000000), '1.50 s');
    });
  });
}
