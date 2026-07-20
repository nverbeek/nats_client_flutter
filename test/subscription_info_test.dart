import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/subscription_info.dart';

void main() {
  group('encodeSubscriptionList / decodeSubscriptionList', () {
    test('round-trips subject and queue group', () {
      final original = [
        SubscriptionInfo(
            subject: 'orders.*', queueGroup: 'workers', colorIndex: 0),
        SubscriptionInfo(subject: 'alerts', colorIndex: 1),
      ];

      final decoded = decodeSubscriptionList(encodeSubscriptionList(original));

      expect(decoded.length, 2);
      expect(decoded[0].subject, 'orders.*');
      expect(decoded[0].queueGroup, 'workers');
      expect(decoded[1].subject, 'alerts');
      expect(decoded[1].queueGroup, isNull);
    });

    test('sid and colorIndex are never persisted', () {
      final original = [
        SubscriptionInfo(subject: 'orders.*', colorIndex: 5, sid: 42),
      ];

      final json = encodeSubscriptionList(original);
      expect(json.contains('42'), isFalse);
      expect(json.contains('sid'), isFalse);

      final decoded = decodeSubscriptionList(json, startColorIndex: 3);
      expect(decoded.single.colorIndex, 3);
      expect(decoded.single.sid, isNull);
    });

    test('assigns sequential colorIndex from startColorIndex in list order',
        () {
      final original = [
        SubscriptionInfo(subject: 'a', colorIndex: 0),
        SubscriptionInfo(subject: 'b', colorIndex: 0),
        SubscriptionInfo(subject: 'c', colorIndex: 0),
      ];

      final decoded = decodeSubscriptionList(encodeSubscriptionList(original),
          startColorIndex: 7);

      expect(decoded.map((s) => s.colorIndex).toList(), [7, 8, 9]);
    });

    test('empty list round-trips to empty list', () {
      expect(decodeSubscriptionList(encodeSubscriptionList([])), isEmpty);
    });
  });

  group('migrateFromLegacySubject', () {
    test('splits on comma, trims whitespace, drops empty segments', () {
      final migrated = migrateFromLegacySubject(' orders.* ,, alerts ,  ');

      expect(migrated.map((s) => s.subject).toList(), ['orders.*', 'alerts']);
      expect(migrated.every((s) => s.queueGroup == null), isTrue);
    });

    test('assigns sequential colorIndex starting at startColorIndex', () {
      final migrated = migrateFromLegacySubject('a,b,c', startColorIndex: 2);

      expect(migrated.map((s) => s.colorIndex).toList(), [2, 3, 4]);
    });

    test('a single subject with no commas migrates to one entry', () {
      final migrated = migrateFromLegacySubject('>');
      expect(migrated.length, 1);
      expect(migrated.single.subject, '>');
    });
  });

  group('resolveSubscriptionColor', () {
    test('cycles the palette when colorIndex exceeds palette length', () {
      final colorAtZero = resolveSubscriptionColor(0, true);
      final colorWrapped =
          resolveSubscriptionColor(8, true); // dark palette has 8 entries
      expect(colorWrapped, colorAtZero);
    });

    test('dark and light resolutions can differ for the same index', () {
      final dark = resolveSubscriptionColor(0, true);
      final light = resolveSubscriptionColor(0, false);
      // not asserting a specific relationship beyond "this is theme-aware"
      expect(dark, isNotNull);
      expect(light, isNotNull);
    });
  });
}
