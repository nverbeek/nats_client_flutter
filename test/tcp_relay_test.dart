import 'package:dart_nats/dart_nats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/tcp_relay.dart';

void main() {
  group('tcpRelayUri', () {
    test('uses ws on the page origin for an http page', () {
      final uri =
          tcpRelayUri(Uri.parse('http://localhost:8080/#/'), 'nats-js', '4222');
      expect(uri.toString(),
          'ws://localhost:8080/nats-tcp?host=nats-js&port=4222');
    });

    test('uses wss for an https page', () {
      final uri =
          tcpRelayUri(Uri.parse('https://example.com/'), 'nats-js', '4222');
      expect(uri.scheme, 'wss');
      expect(uri.host, 'example.com');
      expect(uri.hasPort, isFalse);
    });

    test('resolves relative to a sub-path the app is served under', () {
      final uri = tcpRelayUri(
          Uri.parse('https://example.com/tools/nats/index.html?x=1#/'),
          'h',
          '1');
      expect(uri.path, '/tools/nats/nats-tcp');
      expect(uri.queryParameters, {'host': 'h', 'port': '1'});
      expect(uri.fragment, isEmpty);
    });

    test('passes a bracketed IPv6 host as the bare address', () {
      final uri = tcpRelayUri(Uri.parse('http://localhost/'), '[::1]', '4222');
      expect(uri.queryParameters['host'], '::1');
    });
  });

  group('tcpRelayRefusalReason', () {
    test('extracts the reason from a relay -ERR', () {
      final error = NatsException.fromServerError(
          "'NATS TCP relay: cannot reach nats-js:4222 (Connection refused)'");
      expect(tcpRelayRefusalReason(error),
          'cannot reach nats-js:4222 (Connection refused)');
    });

    test('is null for other errors', () {
      expect(
          tcpRelayRefusalReason(
              NatsException.fromServerError("'Authorization Violation'")),
          isNull);
      expect(tcpRelayRefusalReason(Exception('NATS TCP relay: x')), isNull);
    });
  });
}
