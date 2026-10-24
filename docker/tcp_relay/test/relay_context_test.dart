import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_nats/dart_nats.dart';
import 'package:http/http.dart' as http;
import 'package:nats_tcp_relay/context.dart';
import 'package:nats_tcp_relay/relay.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const nonce = 'test-nonce-123';

/// A minimal NATS server: sends INFO (with a nonce), records the client's
/// CONNECT line and answers PING. With [tls], it asks for TLS and upgrades
/// after INFO the way nats-server does; with [tlsFirst], TLS comes first.
class FakeNats {
  FakeNats({this.tls, this.tlsFirst = false, this.requireClientCert = false});

  final SecurityContext? tls;
  final bool tlsFirst;
  final bool requireClientCert;
  final connect = Completer<Map<String, dynamic>>();

  /// Every CONNECT received, in order.
  final connects = <Map<String, dynamic>>[];
  late final Future<void> Function() _close;
  late int port;

  Future<void> start() async {
    if (tlsFirst) {
      final server = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4, 0, tls!,
          requireClientCertificate: requireClientCert);
      port = server.port;
      _close = server.close;
      server.listen((s) {
        s.add(utf8.encode(_info()));
        _serve(s);
      }, onError: (Object _) {});
      return;
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    _close = server.close;
    server.listen((socket) async {
      socket.add(utf8.encode(_info()));
      if (tls == null) return _serve(socket);
      try {
        _serve(await SecureSocket.secureServer(socket, tls!,
            requireClientCertificate: requireClientCert));
      } catch (_) {
        socket.destroy();
      }
    });
  }

  String _info() => 'INFO ${jsonEncode({
            'server_id': 'fake',
            'proto': 1,
            'max_payload': 1048576,
            'nonce': nonce,
            if (tls != null) 'tls_required': true,
          })}\r\n';

  void _serve(Socket socket) {
    socket.listen((data) {
      for (final line in utf8.decode(data, allowMalformed: true).split('\n')) {
        if (line.startsWith('CONNECT ')) {
          final options =
              jsonDecode(line.substring(8).trim()) as Map<String, dynamic>;
          connects.add(options);
          if (!connect.isCompleted) connect.complete(options);
        }
        if (line.startsWith('PING')) socket.add(utf8.encode('PONG\r\n'));
      }
    }, onError: (Object _) {});
  }

  Future<void> close() => _close();
}

/// Throwaway certificates from openssl: a CA, a server cert for 127.0.0.1
/// signed by it, and a client cert for mTLS.
class TestCerts {
  TestCerts(this.dir);
  final String dir;
  String get ca => '$dir/ca.pem';
  String get clientCert => '$dir/client.pem';
  String get clientKey => '$dir/client.key';

  SecurityContext server({bool trustClients = false}) {
    final context = SecurityContext()
      ..useCertificateChain('$dir/server.pem')
      ..usePrivateKey('$dir/server.key');
    if (trustClients) context.setTrustedCertificates(ca);
    return context;
  }

  static Future<TestCerts?> create(String dir) async {
    // Config files rather than -subj, which Git Bash's openssl would
    // mangle into a Windows path.
    File('$dir/ca.cnf').writeAsStringSync('''
[req]
prompt = no
distinguished_name = dn
x509_extensions = ext
[dn]
CN = relay-test-ca
[ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
''');
    for (final name in ['server', 'client']) {
      File('$dir/$name.cnf').writeAsStringSync(
          '[req]\nprompt = no\ndistinguished_name = dn\n[dn]\nCN = $name\n');
    }
    File('$dir/server.ext').writeAsStringSync(
        'subjectAltName = IP:127.0.0.1\nextendedKeyUsage = serverAuth\n');
    File('$dir/client.ext')
        .writeAsStringSync('extendedKeyUsage = clientAuth\n');
    final steps = [
      'req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 2 -config ca.cnf',
      for (final name in ['server', 'client']) ...[
        'req -newkey rsa:2048 -nodes -keyout $name.key -out $name.csr -config $name.cnf',
        'x509 -req -in $name.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out $name.pem -days 2 -extfile $name.ext',
      ],
    ];
    for (final step in steps) {
      try {
        final result = await Process.run('openssl', step.split(' '),
            workingDirectory: dir);
        if (result.exitCode != 0) {
          throw StateError('openssl $step failed: ${result.stderr}');
        }
      } on ProcessException {
        return null;
      }
    }
    return TestCerts(dir);
  }
}

void main() {
  late Directory tmp;
  late Directory webRoot;
  HttpServer? relayServer;
  final servers = <FakeNats>[];
  TestCerts? certs;
  bool hasOpenssl;
  try {
    hasOpenssl = Process.runSync('openssl', ['version']).exitCode == 0;
  } on ProcessException {
    hasOpenssl = false;
  }

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('relay_certs');
    certs = await TestCerts.create(dir.path);
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('relay_ctx');
    webRoot = Directory('${tmp.path}/web')..createSync();
    File('${webRoot.path}/index.html').writeAsStringSync('app');
  });

  tearDown(() async {
    await relayServer?.close(force: true);
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
    await tmp.delete(recursive: true);
  });

  Future<FakeNats> fake(
      {SecurityContext? tls,
      bool tlsFirst = false,
      bool requireClientCert = false}) async {
    final server = FakeNats(
        tls: tls, tlsFirst: tlsFirst, requireClientCert: requireClientCert);
    await server.start();
    servers.add(server);
    return server;
  }

  Future<String> startRelay(List<NatsContext> contexts,
      {Set<String> allowed = const {},
      Set<String> allowedOrigins = const {}}) async {
    relayServer = await shelf_io.serve(
        createHandler(
            webRoot: webRoot.path,
            relay: RelayConfig(
                allowedHosts: allowed,
                allowedOrigins: allowedOrigins,
                contexts: ContextSet(contexts,
                    selected: contexts.isEmpty ? null : contexts.first.name)),
            log: (_) {}),
        InternetAddress.loopbackIPv4,
        0);
    return '127.0.0.1:${relayServer!.port}';
  }

  /// Connects through the relay like the app does: waits for INFO, sends
  /// CONNECT (with [browserAuth]) and PING, and returns everything received
  /// once a PONG or an error arrives.
  Future<String> session(String relay, Map<String, String> query,
      {Map<String, dynamic> browserAuth = const {},
      Map<String, String> headers = const {}}) async {
    final ws = IOWebSocketChannel.connect(
        Uri.parse('ws://$relay/$relayPath').replace(queryParameters: query),
        headers: headers);
    await ws.ready;
    final received = StringBuffer();
    final done = Completer<void>();
    var sent = false;
    ws.stream.listen((dynamic data) {
      received.write(data is String ? data : utf8.decode(data as List<int>));
      final text = received.toString();
      if (!sent && text.startsWith('INFO ')) {
        sent = true;
        ws.sink.add(utf8.encode(
            'CONNECT ${jsonEncode({'verbose': false, ...browserAuth})}\r\n'
            'PING\r\n'));
      }
      if ((text.contains('PONG') || text.contains('-ERR')) &&
          !done.isCompleted) {
        done.complete();
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 10));
    await ws.sink.close();
    return received.toString();
  }

  NatsContext context(FakeNats server,
          {String name = 'ctx',
          String user = '',
          String password = '',
          String nkeySeed = '',
          String jwt = '',
          String seed = '',
          String? ca,
          String? cert,
          String? key,
          bool tlsFirst = false,
          bool tls = false}) =>
      NatsContext(
          name: name,
          servers: [ContextServer('127.0.0.1', server.port, tls: tls)],
          user: user,
          password: password,
          nkeySeed: nkeySeed,
          jwt: jwt,
          seed: seed,
          ca: ca,
          cert: cert,
          key: key,
          tlsFirst: tlsFirst);

  test('connects as a context, replacing the browser\'s credentials', () async {
    final server = await fake();
    final relay =
        await startRelay([context(server, user: 'alice', password: 's3cret')]);
    final received = await session(relay, {'context': 'ctx'},
        browserAuth: {'auth_token': 'from-the-browser'});
    expect(received, contains('PONG'));
    final connect = await server.connect.future;
    expect(connect['user'], 'alice');
    expect(connect['pass'], 's3cret');
    expect(connect.containsKey('auth_token'), isFalse);
    expect(connect['verbose'], isFalse, reason: 'other options kept');
  });

  test('signs the server nonce for an NKey context', () async {
    final server = await fake();
    final user = Nkeys.createUser();
    final relay = await startRelay([context(server, nkeySeed: user.seed)]);
    expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
    final connect = await server.connect.future;
    expect(connect['nkey'], user.publicKey());
    expect(
        Nkeys.verify(user.publicKey(), utf8.encode(nonce),
            base64.decode(connect['sig'] as String)),
        isTrue);
  });

  test('sends a JWT and its signature for a creds context', () async {
    final server = await fake();
    final user = Nkeys.createUser();
    final relay = await startRelay(
        [context(server, jwt: 'the.user.jwt', seed: user.seed)]);
    expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
    final connect = await server.connect.future;
    expect(connect['jwt'], 'the.user.jwt');
    expect(
        Nkeys.verify(user.publicKey(), utf8.encode(nonce),
            base64.decode(connect['sig'] as String)),
        isTrue);
  });

  test('passes the browser\'s own credentials through for a plain host',
      () async {
    final server = await fake();
    final relay = await startRelay([]);
    await session(relay, {'host': '127.0.0.1', 'port': '${server.port}'},
        browserAuth: {'auth_token': 'from-the-browser'});
    expect((await server.connect.future)['auth_token'], 'from-the-browser');
  });

  test('refuses an unknown or unusable context', () async {
    final server = await fake();
    final broken = NatsContext(
        name: 'broken', servers: const [], error: 'creds file missing');
    final relay = await startRelay([context(server), broken]);
    expect(await session(relay, {'context': 'nope'}),
        contains('there is no context named "nope"'));
    expect(await session(relay, {'context': 'broken'}),
        contains('context "broken" is unusable: creds file missing'));
  });

  test('tries a context\'s servers in order', () async {
    final down = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final downPort = down.port;
    await down.close();
    final server = await fake();
    final ctx = NatsContext(name: 'cluster', servers: [
      ContextServer('127.0.0.1', downPort),
      ContextServer('127.0.0.1', server.port),
    ]);
    final relay = await startRelay([ctx]);
    expect(await session(relay, {'context': 'cluster'}), contains('PONG'));
  });

  test('with contexts loaded, any host is still allowed by address', () async {
    final ctxServer = await fake();
    final other = await fake();
    final relay = await startRelay([context(ctxServer)]);
    expect(await session(relay, {'host': '127.0.0.1', 'port': '${other.port}'}),
        contains('PONG'));
  });

  test('NATS_TCP_ALLOWED_HOSTS limits hosts, but not contexts', () async {
    final ctxServer = await fake();
    final listed = await fake();
    final other = await fake();
    final relay = await startRelay([context(ctxServer)],
        allowed: {'127.0.0.1:${listed.port}'});
    expect(
        await session(relay, {'host': '127.0.0.1', 'port': '${listed.port}'}),
        contains('PONG'));
    expect(await session(relay, {'host': '127.0.0.1', 'port': '${other.port}'}),
        contains('is not in NATS_TCP_ALLOWED_HOSTS'));
    expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
  });

  group('which pages may use the relay', () {
    test('refuses a page with no origin of its own (Origin: null)', () async {
      // Any site can make one: a sandboxed iframe, with or without contexts.
      final server = await fake();
      for (final contexts in [
        <NatsContext>[],
        [context(server)]
      ]) {
        final relay = await startRelay(contexts);
        expect(
            await session(
                relay, {'host': '127.0.0.1', 'port': '${server.port}'},
                headers: {'Origin': 'null'}),
            contains('has no origin of its own'));
        await relayServer!.close(force: true);
      }
      expect(server.connects, isEmpty);
      expect(RelayConfig.parseAllowedOrigins('null, https://ok.example'),
          {'https://ok.example'},
          reason: 'null can never be allowed');
    });

    test('a forged X-Forwarded-Host does not get past the host check',
        () async {
      final server = await fake();
      final relay = await startRelay([context(server)]);
      final port = relay.split(':').last;
      // What a DNS-rebinding page's own fetch() may send.
      final forged =
          await http.get(Uri.parse('http://$relay/$contextsPath'), headers: {
        'Host': 'rebind.example:$port',
        'X-Forwarded-Host': 'localhost:$port',
      });
      expect(forged.statusCode, 403);
      expect(forged.body, isNot(contains('"ctx"')));
    });

    test('refuses a page from another site', () async {
      final server = await fake();
      final relay = await startRelay([context(server)]);
      final received = await session(relay, {'context': 'ctx'},
          headers: {'Origin': 'https://evil.example'});
      expect(received, contains('is not the one the relay serves'));
      expect(server.connects, isEmpty);
    });

    test('allows its own page, a listed one, and non-browser clients',
        () async {
      final server = await fake();
      final relay = await startRelay([context(server)],
          allowedOrigins: {'https://nats-ui.example.com'});
      expect(
          await session(relay, {'context': 'ctx'},
              headers: {'Origin': 'http://$relay'}),
          contains('PONG'));
      expect(
          await session(relay, {
            'context': 'ctx'
          }, headers: {
            'Origin': 'https://nats-ui.example.com',
            'X-Forwarded-Host': 'internal-name:8080',
          }),
          contains('PONG'),
          reason: 'listed, even though the proxy changed the address');
      expect(await session(relay, {'context': 'ctx'}), contains('PONG'),
          reason: 'no Origin: not a browser');
    });

    test('with contexts, refuses a page under another name (DNS rebinding)',
        () async {
      final server = await fake();
      final relay = await startRelay([context(server)]);
      final port = relay.split(':').last;
      // The browser's Host: the name the page was loaded under.
      Future<String> from(String host) => session(relay, {'context': 'ctx'},
          headers: {'Origin': 'http://$host', 'Host': host});
      expect(await from('rebind.example:$port'),
          contains('can only be used from localhost or an IP address'));
      expect(await from('localhost:$port'), contains('PONG'));
      expect(await from('nats-ui.localhost:$port'), contains('PONG'));
      expect(await from('[::1]:$port'), contains('PONG'));
      expect(server.connects, hasLength(3));
    });

    test('without contexts, any name of its own page is fine', () async {
      final server = await fake();
      final relay = await startRelay([]);
      expect(
          await session(relay, {
            'host': '127.0.0.1',
            'port': '${server.port}'
          }, headers: {
            'Origin': 'https://nats-ui.example.com',
            'X-Forwarded-Host': 'nats-ui.example.com',
          }),
          contains('PONG'));
    });

    test('lists contexts only to an allowed page', () async {
      final server = await fake();
      final relay = await startRelay([context(server)]);
      final refused = await http.get(Uri.parse('http://$relay/$contextsPath'),
          headers: {'Host': 'rebind.example'});
      expect(refused.statusCode, 403);
      expect((jsonDecode(refused.body) as Map)['error'],
          contains('add http://rebind.example to NATS_UI_ALLOWED_ORIGINS'),
          reason: 'the scheme the page was really loaded with');
      final proxied = await http.get(Uri.parse('http://$relay/$contextsPath'),
          headers: {'Host': 'rebind.example', 'X-Forwarded-Proto': 'https'});
      expect(proxied.body, contains('add https://rebind.example'));
      expect(refused.body, isNot(contains('"ctx"')));
    });
  });

  test('refuses a browser that sends too much, or no UTF-8, before CONNECT',
      () async {
    final server = await fake();
    final relay = await startRelay([context(server, user: 'u', password: 'p')]);
    Future<String> sending(List<int> bytes) async {
      final ws = WebSocketChannel.connect(
          Uri.parse('ws://$relay/$relayPath?context=ctx'));
      await ws.ready;
      final received = StringBuffer();
      final done = Completer<void>();
      ws.stream.listen((dynamic data) {
        received.write(data is String ? data : utf8.decode(data as List<int>));
        if (received.toString().startsWith('INFO ')) ws.sink.add(bytes);
      }, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 10));
      return received.toString();
    }

    expect(await sending(List.filled(70 * 1024, 0x41)), contains('too long'));
    expect(await sending([0xff, 0xfe, 0x0a]), contains('not valid UTF-8'));
    expect(server.connects, isEmpty);
  });

  test('never echoes control characters from the request', () async {
    final relay = await startRelay([]);
    final received =
        await session(relay, {'context': 'x\r\nINFO {"forged":true}'});
    expect(received, contains('there is no context named'));
    expect(received, isNot(contains('\nINFO')));
  });

  test('uses rotated credentials on the next connection', () async {
    final server = await fake();
    final token = File('${tmp.path}/token')..writeAsStringSync('first');
    final ctx = NatsContext(
        name: 'ctx',
        servers: [ContextServer('127.0.0.1', server.port)],
        files: {'token': token.path});
    final relay = await startRelay([ctx]);
    expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
    token.writeAsStringSync('second');
    expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
    expect(server.connects.map((c) => c['auth_token']), ['first', 'second']);
  });

  test('lists contexts for the app without secrets', () async {
    final server = await fake();
    final relay = await startRelay(
        [context(server, name: 'prod', user: 'alice', password: 's3cret')]);
    final response = await http.get(Uri.parse('http://$relay/$contextsPath'));
    expect(response.statusCode, 200);
    expect(response.body, isNot(contains('s3cret')));
    expect(jsonDecode(response.body), [
      {
        'name': 'prod',
        'description': '',
        'server': 'nats://127.0.0.1:${server.port}',
        'selected': true,
      }
    ]);
  });

  group('TLS', () {
    // Decided when the tests are declared, before setUpAll makes the certs.
    String? skip() => hasOpenssl ? null : 'openssl is not available';

    test('upgrades after INFO when the server requires TLS', () async {
      final server = await fake(tls: certs!.server());
      final relay = await startRelay(
          [context(server, ca: certs!.ca, user: 'u', password: 'p')]);
      final received = await session(relay, {'context': 'ctx'});
      expect(received, contains('PONG'));
      expect(received, contains('"tls_required":true'),
          reason: 'INFO reaches the app unchanged');
      expect((await server.connect.future)['user'], 'u');
    }, skip: skip());

    test('presents a client certificate for mTLS', () async {
      final server = await fake(
          tls: certs!.server(trustClients: true), requireClientCert: true);
      final relay = await startRelay([
        context(server,
            ca: certs!.ca, cert: certs!.clientCert, key: certs!.clientKey)
      ]);
      expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
    }, skip: skip());

    test('does TLS first when the context says tls_first', () async {
      final server = await fake(tls: certs!.server(), tlsFirst: true);
      final relay =
          await startRelay([context(server, ca: certs!.ca, tlsFirst: true)]);
      expect(await session(relay, {'context': 'ctx'}), contains('PONG'));
    }, skip: skip());

    test('refuses a server certificate it cannot verify', () async {
      final server = await fake(tls: certs!.server());
      // No CA: only the system's trusted roots, which don't know this one.
      final relay = await startRelay([context(server)]);
      expect(await session(relay, {'context': 'ctx'}),
          contains('TLS with 127.0.0.1:${server.port} failed'));
    }, skip: skip());

    test('uses TLS for a plain host when the server requires it', () async {
      final server = await fake(tls: certs!.server());
      final relay = await startRelay([]);
      // The test CA isn't a public one, so this proves the attempt is made.
      expect(
          await session(relay, {'host': '127.0.0.1', 'port': '${server.port}'}),
          contains('TLS with 127.0.0.1:${server.port} failed'));
    }, skip: skip());
  });
}
