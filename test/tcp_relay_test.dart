import 'package:dart_nats/dart_nats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('contexts', () {
    test('tcpRelayContextUri names the context, same origin as the page', () {
      expect(
          tcpRelayContextUri(
                  Uri.parse('https://example.com/tools/nats/#/'), 'prod')
              .toString(),
          'wss://example.com/tools/nats/nats-tcp?context=prod');
    });

    test('parses the relay\'s list, server into host and port', () {
      final contexts = parseRelayContexts('''[
        {"name": "prod", "description": "Production",
         "server": "tls://connect.ngs.global:4222", "selected": true},
        {"name": "dev", "server": "nats://localhost", "selected": false,
         "error": "creds file missing"}
      ]''');
      expect(contexts.map((c) => c.name), ['prod', 'dev']);
      expect(contexts[0].host, 'connect.ngs.global');
      expect(contexts[0].port, '4222');
      expect(contexts[0].selected, isTrue);
      expect(contexts[1].port, '4222', reason: 'the default NATS port');
      expect(contexts[1].error, 'creds file missing');
    });

    test('treats anything malformed as no contexts', () {
      expect(parseRelayContexts('not json'), isEmpty);
      expect(parseRelayContexts('{"name": "x"}'), isEmpty);
      expect(parseRelayContexts('[{"description": "no name"}]'), isEmpty);
    });

    test('fetchRelayContexts reads the list next to the page', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
            '[{"name": "prod", "server": "nats://h:4222"}]', 200);
      });
      final (:contexts, :refusal) = await fetchRelayContexts(
          Uri.parse('http://localhost:8080/#/'),
          client: client);
      expect(requested.toString(), 'http://localhost:8080/contexts');
      expect(contexts.single.name, 'prod');
      expect(refusal, isNull);
    });

    test('fetchRelayContexts treats a failure as no contexts', () async {
      final notFound = MockClient((_) async => http.Response('', 404));
      final none =
          await fetchRelayContexts(Uri.parse('http://h/'), client: notFound);
      expect(none.contexts, isEmpty);
      expect(none.refusal, isNull);
      final broken = MockClient((_) async => throw Exception('offline'));
      expect(
          (await fetchRelayContexts(Uri.parse('http://h/'), client: broken))
              .contexts,
          isEmpty);
    });

    test('fetchRelayContexts says why the relay refused this page', () async {
      final forbidden = MockClient((_) async => http.Response(
          '{"error": "add https://ui.example to NATS_UI_ALLOWED_ORIGINS"}',
          403));
      final result =
          await fetchRelayContexts(Uri.parse('http://h/'), client: forbidden);
      expect(result.contexts, isEmpty);
      expect(result.refusal, contains('NATS_UI_ALLOWED_ORIGINS'));
      final proxy = MockClient((_) async => http.Response('Forbidden', 403));
      expect(
          (await fetchRelayContexts(Uri.parse('http://h/'), client: proxy))
              .refusal,
          isNull,
          reason: 'some other 403, not the relay\'s');
    });
  });
}
