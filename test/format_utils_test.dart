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
}
