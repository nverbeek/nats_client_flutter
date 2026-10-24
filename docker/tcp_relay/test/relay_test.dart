import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nats_tcp_relay/relay.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A TCP server that greets each connection with [greeting] (nothing when
/// null) and answers PING with PONG.
Future<ServerSocket> fakeServer(String? greeting) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    if (greeting != null) socket.add(utf8.encode(greeting));
    socket.listen((data) {
      if (utf8.decode(data, allowMalformed: true).contains('PING')) {
        socket.add(utf8.encode('PONG\r\n'));
      }
    }, onError: (Object _) {});
  });
  return server;
}

const natsInfo =
    'INFO {"server_id":"fake","proto":1,"max_payload":1048576}\r\n';

void main() {
  late Directory webRoot;
  late HttpServer relayServer;
  final servers = <ServerSocket>[];

  Future<void> startRelay([RelayConfig? config]) async {
    relayServer = await shelf_io.serve(
        createHandler(webRoot: webRoot.path, relay: config, log: (_) {}),
        InternetAddress.loopbackIPv4,
        0);
  }

  Future<int> target(String? greeting) async {
    final server = await fakeServer(greeting);
    servers.add(server);
    return server.port;
  }

  /// Opens a relay connection and returns everything received until the
  /// relay closes it, or [wait] passes.
  Future<String> receive(String query,
      {List<String> send = const [],
      Duration wait = const Duration(seconds: 3)}) async {
    final ws = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${relayServer.port}/$relayPath?$query'));
    await ws.ready;
    final received = StringBuffer();
    final done = Completer<void>();
    ws.stream.listen((dynamic data) {
      received.write(data is String ? data : utf8.decode(data as List<int>));
      if (received.toString().contains('INFO ')) {
        for (final line in send) {
          ws.sink.add(utf8.encode(line));
        }
        send = const [];
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    await done.future.timeout(wait, onTimeout: () {});
    await ws.sink.close();
    return received.toString();
  }

  setUp(() async {
    webRoot = await Directory.systemTemp.createTemp('relay_web');
    await File('${webRoot.path}/index.html').writeAsString('<p>app</p>');
  });

  tearDown(() async {
    await relayServer.close(force: true);
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
    await webRoot.delete(recursive: true);
  });

  test('relays INFO and traffic in both directions', () async {
    await startRelay();
    final port = await target(natsInfo);
    final received = await receive('host=127.0.0.1&port=$port',
        send: ['PING\r\n'], wait: const Duration(seconds: 1));
    expect(received, startsWith('INFO '));
    expect(received, contains('PONG'));
    expect(received, isNot(contains(relayErrorMarker)));
  });

  test('refuses a target that does not greet like NATS', () async {
    await startRelay();
    final port = await target('HTTP/1.1 400 Bad Request\r\n');
    final received = await receive('host=127.0.0.1&port=$port');
    expect(received, startsWith('-ERR'));
    expect(received, contains('did not answer like a NATS server'));
  });

  test('refuses a silent target after the INFO timeout', () async {
    await startRelay(RelayConfig(infoTimeout: Duration(milliseconds: 200)));
    final port = await target(null);
    final received = await receive('host=127.0.0.1&port=$port');
    expect(received, contains('did not answer like a NATS server'));
  });

  test('attempts TLS with a TLS-required server, and reports failure',
      () async {
    await startRelay();
    // Asks for TLS, then never does the handshake.
    final port = await target('INFO {"tls_required":true}\r\n');
    final received = await receive('host=127.0.0.1&port=$port',
        wait: const Duration(seconds: 8));
    expect(received, contains('TLS with 127.0.0.1:$port'));
  });

  test('refuses an unreachable target', () async {
    await startRelay();
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final received = await receive('host=127.0.0.1&port=$port');
    expect(received, contains('cannot reach 127.0.0.1:$port'));
  });

  test('refuses a missing or invalid port', () async {
    await startRelay();
    expect(await receive('host=127.0.0.1&port=70000'),
        contains('a host and a port'));
    expect(await receive('host=127.0.0.1'), contains('a host and a port'));
  });

  test('only relays to allowed hosts when an allowlist is set', () async {
    final port = await target(natsInfo);
    await startRelay(RelayConfig(allowedHosts: {'127.0.0.1:$port'}));
    expect(
        await receive('host=127.0.0.1&port=$port',
            wait: const Duration(milliseconds: 500)),
        startsWith('INFO '));
    expect(await receive('host=localhost&port=$port'),
        contains('not in NATS_TCP_ALLOWED_HOSTS'));
  });

  test('parses the allowlist environment value', () {
    expect(RelayConfig.parseAllowedHosts(' Nats-A , nats-b:4222,, '),
        {'nats-a', 'nats-b:4222'});
    expect(RelayConfig.parseAllowedHosts(null), isEmpty);
    final config = RelayConfig(allowedHosts: {'nats-a', 'nats-b:4222'});
    expect(config.allows('NATS-A', 1234), isTrue);
    expect(config.allows('nats-b', 4222), isTrue);
    expect(config.allows('nats-b', 4223), isFalse);
  });

  test('serves the web build', () async {
    await startRelay();
    final index =
        await http.get(Uri.parse('http://127.0.0.1:${relayServer.port}/'));
    expect(index.statusCode, 200);
    expect(index.body, contains('app'));
  });

  test('refuses every relay connection, with a reason, when disabled',
      () async {
    await startRelay(RelayConfig(enabled: false));
    final port = await target(natsInfo);
    final received = await receive('host=127.0.0.1&port=$port');
    expect(received, startsWith('-ERR'));
    expect(received, contains('nats:// is turned off on this server'));
  });
}
