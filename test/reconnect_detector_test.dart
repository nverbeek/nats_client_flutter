import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/reconnect_detector.dart';

/// Feeds [statuses] in order, returning the events for which the detector
/// reported a genuine reconnect.
List<Status> firedOn(ReconnectDetector detector, List<Status> statuses) {
  final fired = <Status>[];
  for (final status in statuses) {
    if (detector.onStatus(status)) fired.add(status);
  }
  return fired;
}

void main() {
  group('ReconnectDetector', () {
    test('does not fire on the first connect of a session', () {
      final detector = ReconnectDetector();
      final fired = firedOn(detector, [
        Status.connecting,
        Status.infoHandshake,
        Status.connected,
      ]);
      expect(fired, isEmpty);
    });

    test("fires on dart_nats's real post-bounce sequence", () {
      // The regression this class exists for. `dart_nats` emits
      // `infoHandshake` between `reconnecting` and `connected` (every
      // transport in `Client._connectUri` sets it once the socket is up),
      // so the previous "was the previous status `reconnecting`?" check
      // never fired and every dashboard's recovery handler was dead code.
      final detector = ReconnectDetector();
      firedOn(detector, [
        Status.connecting,
        Status.infoHandshake,
        Status.connected,
      ]);

      final fired = firedOn(detector, [
        Status.disconnected,
        Status.reconnecting,
        Status.infoHandshake,
        Status.connected,
      ]);

      expect(fired, [Status.connected]);
    });

    test('fires once per reconnect, not once per retry attempt', () {
      // `_reconnectLoopBackground` re-emits `reconnecting` on every attempt.
      final detector = ReconnectDetector();
      detector.onStatus(Status.connected);

      final fired = firedOn(detector, [
        Status.disconnected,
        Status.reconnecting,
        Status.reconnecting,
        Status.reconnecting,
        Status.infoHandshake,
        Status.connected,
      ]);

      expect(fired, hasLength(1));
    });

    test('fires again on a second bounce', () {
      final detector = ReconnectDetector();
      detector.onStatus(Status.connected);

      final first = firedOn(
          detector, [Status.disconnected, Status.reconnecting, Status.connected]);
      final second = firedOn(
          detector, [Status.disconnected, Status.reconnecting, Status.connected]);

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('does not fire twice if connected is somehow repeated', () {
      final detector = ReconnectDetector();
      detector.onStatus(Status.connected);

      final fired = firedOn(detector, [
        Status.disconnected,
        Status.connected,
        Status.connected,
      ]);

      expect(fired, hasLength(1));
    });

    test('handles a TLS handshake in the reconnect path', () {
      final detector = ReconnectDetector();
      detector.onStatus(Status.connected);

      final fired = firedOn(detector, [
        Status.disconnected,
        Status.reconnecting,
        Status.tlsHandshake,
        Status.infoHandshake,
        Status.connected,
      ]);

      expect(fired, [Status.connected]);
    });

    test('fires when a dead connection goes straight to reconnecting', () {
      // The ping-timer path can set `reconnecting` without an intervening
      // `disconnected` event reaching us first.
      final detector = ReconnectDetector();
      detector.onStatus(Status.connected);

      final fired = firedOn(
          detector, [Status.reconnecting, Status.infoHandshake, Status.connected]);

      expect(fired, [Status.connected]);
    });

    test('a retried first connect is still a first connect', () {
      // The initial connect loop also emits `reconnecting` for attempts past
      // the first; there's nothing to recover from yet, so no fire.
      final detector = ReconnectDetector();
      final fired = firedOn(detector, [
        Status.connecting,
        Status.reconnecting,
        Status.reconnecting,
        Status.infoHandshake,
        Status.connected,
      ]);

      expect(fired, isEmpty);
    });

    test('reset makes the next connect a first connect again', () {
      // A new `Client` (explicit Disconnect, or a fresh natsConnect) must
      // not report a reconnect carried over from the previous connection.
      final detector = ReconnectDetector();
      detector.onStatus(Status.connected);
      detector.onStatus(Status.disconnected);

      detector.reset();

      expect(detector.hasConnected, isFalse);
      expect(detector.onStatus(Status.connected), isFalse);
    });
  });
}
