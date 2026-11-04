import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nats_tcp_relay/context.dart';
import 'package:nats_tcp_relay/relay.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// The `nats-monitor` proxy, against fake HTTP servers standing in for a
/// nats-server's monitoring port (and for things that aren't one).
void main() {
  late Directory webRoot;
  late HttpServer relayServer;
  final targets = <HttpServer>[];
  final logs = <String>[];

  Future<void> startRelay([RelayConfig? config]) async {
    relayServer = await shelf_io.serve(
        createHandler(webRoot: webRoot.path, relay: config, log: logs.add),
        InternetAddress.loopbackIPv4,
        0);
  }

  /// A fake monitoring port. [handler] answers each request; the requested
  /// URIs are collected in [seen].
  Future<int> target(void Function(HttpRequest request) handler,
      {List<Uri>? seen}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    targets.add(server);
    server.listen((request) {
      seen?.add(request.uri);
      handler(request);
    });
    return server.port;
  }

  void json(HttpRequest request, Object body, {int status = 200}) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  Future<http.Response> get(String query, {Map<String, String>? headers}) =>
      http.get(
          Uri.parse('http://127.0.0.1:${relayServer.port}/$monitorPath?$query'),
          headers: headers);

  setUp(() async {
    logs.clear();
    webRoot = await Directory.systemTemp.createTemp('relay_web');
  });

  tearDown(() async {
    await relayServer.close(force: true);
    for (final t in targets) {
      await t.close(force: true);
    }
    targets.clear();
    await webRoot.delete(recursive: true);
  });

  test('passes on /varz from the target', () async {
    final seen = <Uri>[];
    final port = await target(
        (r) => json(r, {'server_id': 'NABC', 'version': '2.11.4'}),
        seen: seen);
    await startRelay();

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body)['version'], '2.11.4');
    expect(response.headers['cache-control'], 'no-store');
    expect(seen.single.path, '/varz');
  });

  test('forwards connz paging and sort, capping limit, dropping the rest',
      () async {
    final seen = <Uri>[];
    final port = await target(
        (r) => json(r, {'server_id': 'NABC', 'connections': []}),
        seen: seen);
    await startRelay();

    final response = await get('path=connz&host=127.0.0.1&port=$port'
        '&sort=msgs_to&offset=25&limit=5000&subs=detail&auth=1');
    expect(response.statusCode, 200);
    expect(seen.single.queryParameters,
        {'sort': 'msgs_to', 'offset': '25', 'limit': '100'});
  });

  test('refuses an unknown sort and an unknown path', () async {
    final port = await target((r) => json(r, {'server_id': 'NABC'}));
    await startRelay();

    final badSort = await get('path=connz&host=127.0.0.1&port=$port&sort=name');
    expect(badSort.statusCode, 400);
    final badPath = await get('path=accountz&host=127.0.0.1&port=$port');
    expect(badPath.statusCode, 400);
    expect(jsonDecode(badPath.body)['error'], contains('varz'));
  });

  test('a web page that is not a monitoring endpoint is not passed on',
      () async {
    final port = await target((r) => r.response
      ..headers.contentType = ContentType.html
      ..write('<html>admin console</html>')
      ..close());
    await startRelay();

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 502);
    expect(response.body, isNot(contains('admin console')));
    expect(jsonDecode(response.body)['error'],
        contains('did not answer like a NATS monitoring endpoint'));
  });

  test('JSON without a server_id is not passed on either', () async {
    final port = await target((r) => json(r, {'secret': 'value'}));
    await startRelay();

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 502);
    expect(response.body, isNot(contains('value')));
  });

  test('a redirect is not followed', () async {
    final port = await target((r) => r.response
      ..statusCode = 302
      ..headers.set('location', 'http://169.254.169.254/latest/meta-data')
      ..close());
    await startRelay();

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 502);
  });

  test('an unhealthy /healthz is passed on as 503 with its reason', () async {
    final port = await target((r) => json(
        r, {'status': 'unavailable', 'error': 'JetStream not current'},
        status: 503));
    await startRelay();

    final response = await get('path=healthz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 503);
    expect(jsonDecode(response.body)['status'], 'unavailable');
  });

  test('a closed port is 504, so the app can tell it from a refusal', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await startRelay();

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 504);
    expect(jsonDecode(response.body)['error'], contains('could not reach'));
  });

  test('a target that never answers times out as 504', () async {
    final port = await target((_) {});
    await startRelay(
        RelayConfig(monitorTimeout: const Duration(milliseconds: 300)));

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 504);
    expect(jsonDecode(response.body)['error'], contains('in time'));
  });

  test('NATS_TCP_ALLOWED_HOSTS applies', () async {
    final port = await target((r) => json(r, {'server_id': 'NABC'}));
    await startRelay(RelayConfig(allowedHosts: {'nats-js'}));

    final response = await get('path=varz&host=127.0.0.1&port=$port');
    expect(response.statusCode, 403);
    expect(
        jsonDecode(response.body)['error'], contains('NATS_TCP_ALLOWED_HOSTS'));
  });

  test('another site cannot use it from a visitor\'s browser', () async {
    final port = await target((r) => json(r, {'server_id': 'NABC'}));
    await startRelay();

    final response = await get('path=varz&host=127.0.0.1&port=$port',
        headers: {'origin': 'https://evil.example'});
    expect(response.statusCode, 403);
    expect(logs.single, contains('monitor refused'));
  });

  test('turned off with NATS_TCP_RELAY=off', () async {
    await startRelay(RelayConfig(enabled: false));
    final response = await get('path=varz&host=127.0.0.1&port=8222');
    expect(response.statusCode, 503);
    expect(jsonDecode(response.body)['error'], contains('NATS_TCP_RELAY=off'));
  });

  test('a context is fetched from its own server, at the given port', () async {
    final seen = <Uri>[];
    final port =
        await target((r) => json(r, {'server_id': 'NCTX'}), seen: seen);
    await startRelay(RelayConfig(
        // Contexts never narrow by allowlist, as for the TCP relay.
        allowedHosts: {'somewhere-else'},
        contexts: ContextSet([
          NatsContext(
              name: 'prod', servers: const [ContextServer('127.0.0.1', 4222)]),
        ])));

    final response = await get('path=varz&context=prod&port=$port');
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body)['server_id'], 'NCTX');
    expect(seen, hasLength(1));
  });

  test('an unknown context is refused', () async {
    await startRelay();
    final response = await get('path=varz&context=nope&port=8222');
    expect(response.statusCode, 404);
  });
}
