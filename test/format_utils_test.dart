import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/format_utils.dart';

void main() {
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
