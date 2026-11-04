import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nats_client_flutter/server_monitor.dart';

/// A trimmed but real-shaped `/varz` (nats-server 2.11), timestamps with
/// nanoseconds and an offset like the server sends.
Map<String, dynamic> varzJson({
  String serverId = 'NCXK7Q4ZJ2R5',
  String start = '2026-10-31T09:14:02.123456789-05:00',
  String now = '2026-11-03T13:26:10.987654321-05:00',
  int inMsgs = 1000,
  int outMsgs = 3000,
  int inBytes = 236000,
  int outBytes = 723000,
  bool jetStream = true,
}) =>
    {
      'server_id': serverId,
      'server_name': 'nats-east-1',
      'version': '2.11.4',
      'go': 'go1.24.3',
      'host': '0.0.0.0',
      'port': 4222,
      'max_payload': 1048576,
      'auth_required': true,
      'start': start,
      'now': now,
      'uptime': '3d4h12m8s',
      'mem': 88290918,
      'cores': 8,
      'cpu': 12.4,
      'connections': 312,
      'subscriptions': 4812,
      'in_msgs': inMsgs,
      'out_msgs': outMsgs,
      'in_bytes': inBytes,
      'out_bytes': outBytes,
      'slow_consumers': 0,
      'routes': 2,
      'remotes': 2,
      'leafnodes': 3,
      'cluster': {'name': 'east', 'addr': '0.0.0.0', 'cluster_port': 6222},
      'gateway': <String, dynamic>{},
      if (jetStream)
        'jetstream': {
          'config': {'max_memory': 1024, 'domain': 'hub'},
        },
    };

Map<String, dynamic> connzJson() => {
      'server_id': 'NCXK7Q4ZJ2R5',
      'now': '2026-11-03T18:26:10.000000000Z',
      'num_connections': 2,
      'total': 312,
      'offset': 25,
      'limit': 25,
      'connections': [
        {
          'cid': 1042,
          'ip': '10.0.3.17',
          'port': 51544,
          'start': '2026-11-03T15:26:10.000000000Z',
          'pending_bytes': 512,
          'in_msgs': 10,
          'out_msgs': 9000,
          'subscriptions': 14,
          'name': 'orders-svc-3',
          'lang': 'go',
          'version': '1.41.2',
        },
        {
          'cid': 1043,
          'ip': '::1',
          'port': 51545,
          'subscriptions': 1,
        },
      ],
    };

ServerMonitorClient clientFor(MockClientHandler handler,
        {MonitorEndpoint? endpoint}) =>
    ServerMonitorClient(endpoint ?? DirectMonitorEndpoint('127.0.0.1', 8222),
        client: MockClient(handler));

Matcher throwsMonitor(MonitorErrorKind kind) =>
    throwsA(isA<MonitorException>().having((e) => e.kind, 'kind', kind));

void main() {
  group('ServerVarz', () {
    test('parses identity, load and topology', () {
      final varz = ServerVarz.fromJson(varzJson());
      expect(varz.serverId, 'NCXK7Q4ZJ2R5');
      expect(varz.serverName, 'nats-east-1');
      expect(varz.version, '2.11.4');
      expect(varz.goVersion, 'go1.24.3');
      expect(varz.connections, 312);
      expect(varz.subscriptions, 4812);
      expect(varz.cpu, 12.4);
      expect(varz.cores, 8);
      expect(varz.maxPayload, 1048576);
      expect(varz.authRequired, isTrue);
      expect(varz.tlsRequired, isFalse);
      expect(varz.routes, 2);
      expect(varz.leafnodes, 3);
      expect(varz.clusterName, 'east');
      // An empty gateway block means no gateway is configured.
      expect(varz.gatewayName, isNull);
      expect(varz.jetStreamEnabled, isTrue);
      expect(varz.jetStreamDomain, 'hub');
    });

    test('reads nanosecond timestamps with an offset', () {
      final varz = ServerVarz.fromJson(varzJson());
      expect(varz.start, DateTime.utc(2026, 10, 31, 14, 14, 2, 123, 456));
      expect(varz.uptime!.inHours, 3 * 24 + 4);
    });

    test('a missing field reads as empty instead of throwing', () {
      final varz = ServerVarz.fromJson({'server_id': 'X', 'cpu': 'oops'});
      expect(varz.serverName, '');
      expect(varz.cpu, 0);
      expect(varz.start, isNull);
      expect(varz.uptime, isNull);
      expect(varz.jetStreamEnabled, isFalse);
    });
  });

  group('ConnzPage', () {
    test('parses the page and each connection', () {
      final page = ConnzPage.fromJson(connzJson());
      expect(page.total, 312);
      expect(page.offset, 25);
      expect(page.limit, 25);
      expect(page.connections, hasLength(2));
      final c = page.connections.first;
      expect(c.cid, 1042);
      expect(c.name, 'orders-svc-3');
      expect(c.address, '10.0.3.17:51544');
      expect(c.client, 'go 1.41.2');
      expect(c.pendingBytes, 512);
      expect(c.inMsgs, 10);
      expect(c.outMsgs, 9000);
      expect(c.uptime, const Duration(hours: 3));
    });

    test('brackets an IPv6 address and tolerates missing fields', () {
      final c = ConnzPage.fromJson(connzJson()).connections.last;
      expect(c.address, '[::1]:51545');
      expect(c.client, '');
      expect(c.uptime, isNull);
    });
  });

  group('MonitorEndpoint', () {
    test('direct goes to the host and port over http', () {
      final endpoint = DirectMonitorEndpoint('127.0.0.1', 8222);
      expect(endpoint.uri('connz', {'sort': 'msgs_to'}).toString(),
          'http://127.0.0.1:8222/connz?sort=msgs_to');
      expect(endpoint.label, 'http://127.0.0.1:8222');
    });

    test('direct handles IPv6, bracketed or not', () {
      expect(DirectMonitorEndpoint('::1', 8222).uri('varz').toString(),
          'http://[::1]:8222/varz');
      expect(DirectMonitorEndpoint('[::1]', 8222).uri('varz').toString(),
          'http://[::1]:8222/varz');
      expect(DirectMonitorEndpoint('::1', 8222).label, 'http://[::1]:8222');
    });

    test('relay by host is page-relative and carries the target', () {
      final endpoint = RelayMonitorEndpoint.host(
          Uri.parse('https://example.com/nats/'), 'nats-js', 8222);
      final uri = endpoint.uri('connz', {'sort': 'cid'});
      expect(uri.scheme, 'https');
      expect(uri.path, '/nats/nats-monitor');
      expect(uri.queryParameters, {
        'sort': 'cid',
        'path': 'connz',
        'host': 'nats-js',
        'port': '8222',
      });
    });

    test('relay by context names the context, not a host', () {
      final endpoint = RelayMonitorEndpoint.context(
          Uri.parse('http://localhost:8080/'), 'prod', 8222);
      expect(endpoint.uri('varz').queryParameters,
          {'path': 'varz', 'context': 'prod', 'port': '8222'});
    });
  });

  group('ServerMonitorClient', () {
    test('fetches varz from the endpoint', () async {
      late Uri requested;
      final client = clientFor((request) async {
        requested = request.url;
        return http.Response(jsonEncode(varzJson()), 200);
      });
      final varz = await client.fetchVarz();
      expect(requested.toString(), 'http://127.0.0.1:8222/varz');
      expect(varz.serverName, 'nats-east-1');
    });

    test('asks connz for the sort and page', () async {
      late Uri requested;
      final client = clientFor((request) async {
        requested = request.url;
        return http.Response(jsonEncode(connzJson()), 200);
      });
      final page = await client.fetchConnz(
          sort: ConnzSort.msgsFrom, offset: 25, limit: 25);
      expect(requested.queryParameters,
          {'sort': 'msgs_from', 'offset': '25', 'limit': '25'});
      expect(page.total, 312);
    });

    test('a refused connection is unreachable', () {
      final client =
          clientFor((_) async => throw http.ClientException('refused'));
      expect(client.fetchVarz(), throwsMonitor(MonitorErrorKind.unreachable));
    });

    test('a slow server times out as unreachable', () {
      final client = ServerMonitorClient(
          DirectMonitorEndpoint('127.0.0.1', 8222),
          client: MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(milliseconds: 10));
      expect(client.fetchVarz(), throwsMonitor(MonitorErrorKind.unreachable));
    });

    test('an HTML page on that port is not a monitoring endpoint', () {
      final client =
          clientFor((_) async => http.Response('<html>Grafana</html>', 200));
      expect(client.fetchVarz(), throwsMonitor(MonitorErrorKind.notMonitoring));
    });

    test('JSON without a server_id is not a monitoring endpoint', () {
      final client =
          clientFor((_) async => http.Response('{"status":"ok"}', 200));
      expect(client.fetchVarz(), throwsMonitor(MonitorErrorKind.notMonitoring));
    });

    test('a 404 is not a monitoring endpoint, a 500 is an HTTP error', () {
      expect(clientFor((_) async => http.Response('', 404)).fetchVarz(),
          throwsMonitor(MonitorErrorKind.notMonitoring));
      expect(clientFor((_) async => http.Response('', 500)).fetchVarz(),
          throwsMonitor(MonitorErrorKind.httpError));
    });

    group('https monitoring (https_port, e.g. demo.nats.io)', () {
      const httpsOnly = 'Client sent an HTTP request to an HTTPS server.\n';

      test("switches to https on Go's 'HTTP request to an HTTPS server'",
          () async {
        final schemes = <String>[];
        final endpoint = DirectMonitorEndpoint('demo.nats.io', 8222);
        final client = clientFor((request) async {
          schemes.add(request.url.scheme);
          return request.url.scheme == 'https'
              ? http.Response(jsonEncode(varzJson()), 200)
              : http.Response(httpsOnly, 400);
        }, endpoint: endpoint);

        expect((await client.fetchVarz()).serverName, 'nats-east-1');
        expect(schemes, ['http', 'https']);
        expect(endpoint.label, 'https://demo.nats.io:8222');

        // Later requests go straight to https.
        await client.fetchVarz();
        expect(schemes, ['http', 'https', 'https']);
      });

      test('tries https when http gets no answer (a browser hides the 400)',
          () async {
        final endpoint = DirectMonitorEndpoint('demo.nats.io', 8222);
        final client = clientFor((request) async {
          if (request.url.scheme == 'http') {
            throw http.ClientException('XMLHttpRequest error.');
          }
          return http.Response(jsonEncode(varzJson()), 200);
        }, endpoint: endpoint);

        await client.fetchVarz();
        expect(endpoint.https, isTrue);
      });

      test('when https fails too, the http failure is reported', () async {
        final endpoint = DirectMonitorEndpoint('127.0.0.1', 8222);
        final client = clientFor(
            (request) async =>
                throw http.ClientException('${request.url.scheme} refused'),
            endpoint: endpoint);

        await expectLater(
            client.fetchVarz(),
            throwsA(isA<MonitorException>()
                .having((e) => e.kind, 'kind', MonitorErrorKind.unreachable)
                .having((e) => e.detail, 'detail', contains('http refused'))));
        expect(endpoint.https, isFalse);
        expect(endpoint.label, 'http://127.0.0.1:8222');
      });

      test('a plain http server is never asked over https', () async {
        final schemes = <String>[];
        final client = clientFor((request) async {
          schemes.add(request.url.scheme);
          return http.Response(jsonEncode(varzJson()), 200);
        });
        await client.fetchVarz();
        await client.fetchVarz();
        expect(schemes, ['http', 'http']);
      });

      test('an https page goes straight to https', () async {
        final schemes = <String>[];
        final client = clientFor((request) async {
          schemes.add(request.url.scheme);
          return http.Response(jsonEncode(varzJson()), 200);
        },
            endpoint: DirectMonitorEndpoint('demo.nats.io', 8222,
                blockedByMixedContent: true));
        await client.fetchVarz();
        expect(schemes, ['https']);
      });

      test('an https page that gets no https answer explains why', () {
        final client = clientFor(
            (_) async => throw http.ClientException('XMLHttpRequest error.'),
            endpoint: DirectMonitorEndpoint('127.0.0.1', 8222,
                blockedByMixedContent: true));
        expect(
            client.fetchVarz(), throwsMonitor(MonitorErrorKind.mixedContent));
      });
    });

    test("the relay's refusal is passed on with its reason", () {
      final client = clientFor(
          (_) async => http.Response(
              jsonEncode({'error': 'nats-js is not in NATS_TCP_ALLOWED_HOSTS'}),
              403),
          endpoint: RelayMonitorEndpoint.host(
              Uri.parse('http://localhost:8080/'), 'nats-js', 8222));
      expect(
          client.fetchVarz(),
          throwsA(isA<MonitorException>()
              .having((e) => e.kind, 'kind', MonitorErrorKind.relayRefused)
              .having((e) => e.detail, 'detail',
                  contains('NATS_TCP_ALLOWED_HOSTS'))));
    });

    test("the relay's 504 and 502 mean unreachable and not monitoring", () {
      final relay = RelayMonitorEndpoint.host(
          Uri.parse('http://localhost:8080/'), 'nats-js', 8222);
      expect(
          clientFor(
                  (_) async => http.Response(
                      jsonEncode({'error': 'could not reach nats-js:8222'}),
                      504),
                  endpoint: relay)
              .fetchVarz(),
          throwsA(isA<MonitorException>()
              .having((e) => e.kind, 'kind', MonitorErrorKind.unreachable)
              .having((e) => e.detail, 'detail', contains('nats-js'))));
      expect(
          clientFor(
                  (_) async => http.Response(
                      jsonEncode({'error': 'not a monitoring endpoint'}), 502),
                  endpoint: relay)
              .fetchVarz(),
          throwsMonitor(MonitorErrorKind.notMonitoring));
      expect(
          describeMonitorError(
              const MonitorException(MonitorErrorKind.unreachable,
                  'could not reach nats-js:8222 (Connection refused)'),
              relay),
          'The relay reports: could not reach nats-js:8222 '
          '(Connection refused).');
    });

    test('healthz: 200 is healthy, 503 is an answer with the reason', () async {
      final healthy =
          await clientFor((_) async => http.Response('{"status":"ok"}', 200))
              .fetchHealth();
      expect(healthy.ok, isTrue);

      final unhealthy = await clientFor((_) async => http.Response(
              '{"status":"unavailable","error":"JetStream not current"}', 503))
          .fetchHealth();
      expect(unhealthy.ok, isFalse);
      expect(unhealthy.error, 'JetStream not current');
    });

    test('gatewayz counts outbound gateways', () async {
      final count = await clientFor((_) async => http.Response(
          jsonEncode({
            'server_id': 'X',
            'outbound_gateways': {'west': {}, 'south': {}},
          }),
          200)).fetchGatewayCount();
      expect(count, 2);
    });
  });

  test('describeMonitorError names the endpoint', () {
    final endpoint = DirectMonitorEndpoint('127.0.0.1', 8222);
    expect(
        describeMonitorError(
            const MonitorException(MonitorErrorKind.unreachable), endpoint),
        'No response from http://127.0.0.1:8222.');
    expect(
        describeMonitorError(
            const MonitorException(MonitorErrorKind.relayRefused, 'no'),
            endpoint),
        'The relay refused: no');
  });

  group('ThroughputHistory', () {
    const interval = Duration(seconds: 2);
    ServerVarz at(int second,
            {int inMsgs = 0,
            int outMsgs = 0,
            String serverId = 'A',
            String start = '2026-11-03T00:00:00Z'}) =>
        ServerVarz.fromJson(varzJson(
          serverId: serverId,
          start: start,
          now: DateTime.utc(2026, 11, 3, 12, 0, second).toIso8601String(),
          inMsgs: inMsgs,
          outMsgs: outMsgs,
          inBytes: inMsgs * 100,
          outBytes: outMsgs * 100,
        ));

    test('the first poll only sets a baseline', () {
      final history = ThroughputHistory()..add(at(0), interval: interval);
      expect(history.samples, isEmpty);
    });

    test('rates are the change over the time between polls', () {
      final history = ThroughputHistory()
        ..add(at(0, inMsgs: 100, outMsgs: 300), interval: interval)
        ..add(at(2, inMsgs: 300, outMsgs: 900), interval: interval);
      final s = history.samples.single;
      expect(s.inMsgs, 100);
      expect(s.outMsgs, 300);
      expect(s.inBytes, 10000);
      expect(s.gapBefore, isFalse);
    });

    test('a long wait between polls marks a gap', () {
      final history = ThroughputHistory()
        ..add(at(0), interval: interval)
        ..add(at(2), interval: interval)
        ..add(at(20), interval: interval);
      expect(history.samples.last.gapBefore, isTrue);
    });

    test('samples older than two minutes are dropped', () {
      final history = ThroughputHistory();
      for (var s = 0; s <= 59; s++) {
        history.add(at(s * 2), interval: interval);
      }
      // 59 intervals in 118 s: all inside the window.
      expect(history.samples, hasLength(59));
      history.add(
          ServerVarz.fromJson(varzJson(
              serverId: 'A',
              start: '2026-11-03T00:00:00Z',
              now: DateTime.utc(2026, 11, 3, 12, 2, 10).toIso8601String(),
              inMsgs: 0,
              outMsgs: 0,
              inBytes: 0,
              outBytes: 0)),
          interval: interval);
      final oldest = history.samples.first.time;
      expect(DateTime.utc(2026, 11, 3, 12, 2, 10).difference(oldest),
          lessThanOrEqualTo(ThroughputHistory.window));
    });

    test('a restarted server starts over', () {
      final history = ThroughputHistory()
        ..add(at(0, inMsgs: 500), interval: interval)
        ..add(at(2, inMsgs: 700), interval: interval);
      final before = history.version;
      history.add(
          at(4, inMsgs: 5, serverId: 'B', start: '2026-11-03T12:00:03Z'),
          interval: interval);
      expect(history.samples, isEmpty);
      expect(history.version, greaterThan(before));
      history.add(
          at(6, inMsgs: 25, serverId: 'B', start: '2026-11-03T12:00:03Z'),
          interval: interval);
      expect(history.samples.single.inMsgs, 10);
    });

    test('a counter going backwards also starts over', () {
      final history = ThroughputHistory()
        ..add(at(0, inMsgs: 500), interval: interval)
        ..add(at(2, inMsgs: 700), interval: interval)
        ..add(at(4, inMsgs: 100), interval: interval);
      expect(history.samples, isEmpty);
    });
  });
}
