import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Path (relative to wherever the app is served) of the relay endpoint. Must
/// match `tcpRelayPath` in the app's `lib/tcp_relay.dart`.
const relayPath = 'nats-tcp';

/// Prefix of every `-ERR` the relay sends. The app looks for it to tell a
/// relay refusal apart from a server error. Must match `tcpRelayErrorMarker`
/// in the app's `lib/tcp_relay.dart`.
const relayErrorMarker = 'NATS TCP relay:';

/// Settings for the relay endpoint.
class RelayConfig {
  const RelayConfig({
    this.enabled = true,
    this.allowedHosts = const {},
    this.connectTimeout = const Duration(seconds: 5),
    this.infoTimeout = const Duration(seconds: 5),
  });

  /// When false, every relay connection is refused with a reason the app
  /// shows. The app's Docker build always offers nats://, so a plain 404
  /// would leave it retrying with no explanation.
  final bool enabled;

  /// Lower-case `host` or `host:port` entries a browser may relay to. Empty
  /// allows any target.
  final Set<String> allowedHosts;

  /// How long to wait for the TCP connection to the target.
  final Duration connectTimeout;

  /// How long the target has to send its first line, which must be a NATS
  /// `INFO`. Anything that doesn't greet like a NATS server is refused, so
  /// the relay can't be used as a general TCP proxy.
  final Duration infoTimeout;

  /// Parses a comma-separated `NATS_TCP_ALLOWED_HOSTS` value.
  static Set<String> parseAllowedHosts(String? value) => {
        for (final entry in (value ?? '').split(','))
          if (entry.trim().isNotEmpty) entry.trim().toLowerCase(),
      };

  bool allows(String host, int port) {
    if (allowedHosts.isEmpty) return true;
    final h = host.toLowerCase();
    return allowedHosts.contains(h) || allowedHosts.contains('$h:$port');
  }
}

/// The whole server: the relay endpoint plus the static web build in
/// [webRoot].
Handler createHandler({
  required String webRoot,
  RelayConfig relay = const RelayConfig(),
  void Function(String message) log = print,
}) {
  final staticHandler =
      createStaticHandler(webRoot, defaultDocument: 'index.html');
  return (Request request) {
    if (request.url.path == relayPath) {
      return _relayHandler(request, relay, log);
    }
    return staticHandler(request);
  };
}

FutureOr<Response> _relayHandler(
    Request request, RelayConfig config, void Function(String) log) {
  final host = request.url.queryParameters['host']?.trim() ?? '';
  final port = int.tryParse(request.url.queryParameters['port'] ?? '');
  return webSocketHandler((WebSocketChannel ws, String? _) {
    _Relay(ws, host, port, config, log).start();
  })(request);
}

/// One browser WebSocket paired with one TCP connection to a NATS server.
class _Relay {
  _Relay(this.ws, this.host, this.port, this.config, this.log);

  final WebSocketChannel ws;
  final String host;
  final int? port;
  final RelayConfig config;
  final void Function(String) log;

  Socket? _socket;
  bool _closed = false;

  String get _target => '$host:$port';

  Future<void> start() async {
    final port = this.port;
    if (!config.enabled) {
      return _refuse('nats:// is turned off on this server '
          '(NATS_TCP_RELAY=off). Use ws:// instead');
    }
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      return _refuse('a host and a port between 1 and 65535 are required');
    }
    if (!config.allows(host, port)) {
      return _refuse('$_target is not in NATS_TCP_ALLOWED_HOSTS');
    }

    // Forward anything the browser sends from the start (it normally waits
    // for INFO first), and tear down the TCP side when the browser goes away.
    final pending = <List<int>>[];
    ws.stream.listen((dynamic data) {
      final bytes = data is String ? utf8.encode(data) : data as List<int>;
      final socket = _socket;
      socket == null ? pending.add(bytes) : socket.add(bytes);
    }, onDone: _close, onError: (Object _) => _close());

    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: config.connectTimeout);
    } catch (e) {
      return _refuse('cannot reach $_target (${_describe(e)})');
    }
    if (_closed) {
      socket.destroy();
      return;
    }
    _socket = socket;
    pending.forEach(socket.add);
    pending.clear();

    final greeting = BytesBuilder(copy: false);
    var relaying = false;
    final infoTimer = Timer(config.infoTimeout, () {
      if (!relaying) _refuse('$_target did not answer like a NATS server');
    });
    socket.listen((Uint8List data) {
      if (relaying) {
        ws.sink.add(data);
        return;
      }
      greeting.add(data);
      final bytes = greeting.toBytes();
      final lineEnd = bytes.indexOf(0x0A);
      if (lineEnd < 0) {
        if (bytes.length > 64 * 1024) {
          infoTimer.cancel();
          _refuse('$_target did not answer like a NATS server');
        }
        return;
      }
      infoTimer.cancel();
      final problem = _checkInfo(
          utf8.decode(bytes.sublist(0, lineEnd), allowMalformed: true));
      if (problem != null) {
        _refuse(problem);
        return;
      }
      relaying = true;
      log('relay open: $_target');
      ws.sink.add(bytes);
    }, onDone: () {
      infoTimer.cancel();
      if (!relaying) {
        _refuse('$_target closed the connection before sending INFO');
      } else {
        _close();
      }
    }, onError: (Object _) {
      infoTimer.cancel();
      _close();
    });
  }

  /// Returns why the target's first line isn't acceptable, or null.
  String? _checkInfo(String line) {
    if (!line.startsWith('INFO ')) {
      return '$_target did not answer like a NATS server';
    }
    try {
      final info = jsonDecode(line.substring(5).trim());
      if (info is Map && info['tls_required'] == true) {
        return '$_target requires TLS, which the relay does not support. '
            'Use ws:// or wss:// for this server instead';
      }
    } on FormatException {
      return '$_target sent an INFO that is not valid JSON';
    }
    return null;
  }

  /// Tells the browser why, as a NATS `-ERR` its client will surface, and
  /// closes both sides.
  void _refuse(String reason) {
    if (_closed) return;
    log('relay refused: $reason');
    ws.sink.add(utf8.encode("-ERR '$relayErrorMarker $reason'\r\n"));
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (_socket != null) log('relay closed: $_target');
    _socket?.destroy();
    ws.sink.close();
  }

  static String _describe(Object e) =>
      e is SocketException ? e.message : e.toString();
}
