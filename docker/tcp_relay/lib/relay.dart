import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'context.dart';

/// Path (relative to wherever the app is served) of the relay endpoint. Must
/// match `tcpRelayPath` in the app's `lib/tcp_relay.dart`.
const relayPath = 'nats-tcp';

/// Path of the endpoint listing the contexts the relay can connect as. Must
/// match `tcpRelayContextsPath` in the app's `lib/tcp_relay.dart`.
const contextsPath = 'contexts';

/// Prefix of every `-ERR` the relay sends. The app looks for it to tell a
/// relay refusal apart from a server error. Must match `tcpRelayErrorMarker`
/// in the app's `lib/tcp_relay.dart`.
const relayErrorMarker = 'NATS TCP relay:';

/// Most the browser may send before the server answers, and the longest
/// first `CONNECT` line, like the cap on the server's INFO.
const _maxBrowserBuffer = 64 * 1024;

/// Settings for the relay endpoint.
class RelayConfig {
  RelayConfig({
    this.enabled = true,
    this.allowedHosts = const {},
    this.allowedOrigins = const {},
    ContextSet? contexts,
    this.connectTimeout = const Duration(seconds: 5),
    this.infoTimeout = const Duration(seconds: 5),
    this.pingInterval = const Duration(seconds: 30),
  }) : contexts = contexts ?? ContextSet.empty;

  /// When false, every relay connection is refused with a reason the app
  /// shows. The app's Docker build always offers nats://, so a plain 404
  /// would leave it retrying with no explanation.
  final bool enabled;

  /// Lower-case `host` or `host:port` entries a browser may relay to, from
  /// `NATS_TCP_ALLOWED_HOSTS`. Empty allows any NATS server. Connecting as
  /// a context is always allowed.
  final Set<String> allowedHosts;

  /// Lower-case origins (`https://nats-ui.example.com`) of pages that may
  /// use the relay besides its own, from `NATS_UI_ALLOWED_ORIGINS`. See
  /// [pageRefusal].
  final Set<String> allowedOrigins;

  /// The NATS CLI contexts the browser can connect as.
  final ContextSet contexts;

  /// How long to wait for the TCP connection to the target.
  final Duration connectTimeout;

  /// How long the target has to send its first line, which must be a NATS
  /// `INFO`. Anything that doesn't greet like a NATS server is refused, so
  /// the relay can't be used as a general TCP proxy.
  final Duration infoTimeout;

  /// WebSocket pings to the browser, so proxies that drop idle connections
  /// (nginx's default is 60 seconds) leave a quiet session alone.
  final Duration pingInterval;

  /// Parses a comma-separated `NATS_TCP_ALLOWED_HOSTS` value.
  static Set<String> parseAllowedHosts(String? value) => {
        for (final entry in (value ?? '').split(','))
          if (entry.trim().isNotEmpty) entry.trim().toLowerCase(),
      };

  /// Parses a comma-separated `NATS_UI_ALLOWED_ORIGINS` value, the way
  /// browsers send `Origin`: no trailing slash. Entries that aren't a
  /// `scheme://host` origin are left out (see [invalidOrigins]); so is
  /// `null`, the origin of sandboxed and local-file pages, which any site
  /// can produce.
  static Set<String> parseAllowedOrigins(String? value) => {
        for (final entry in _originEntries(value))
          if (_isOrigin(entry)) entry,
      };

  /// The entries [parseAllowedOrigins] leaves out, for a startup warning.
  static List<String> invalidOrigins(String? value) => [
        for (final entry in _originEntries(value))
          if (!_isOrigin(entry)) entry
      ];

  static Iterable<String> _originEntries(String? value) => [
        for (final entry in (value ?? '').split(','))
          if (entry.trim().isNotEmpty)
            entry.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), ''),
      ];

  static bool _isOrigin(String entry) {
    final uri = Uri.tryParse(entry);
    return uri != null && entry.contains('://') && uri.host.isNotEmpty;
  }

  /// Whether a browser may relay to [host]:[port] by address.
  bool allows(String host, int port) {
    if (allowedHosts.isEmpty) return true;
    final h = host.toLowerCase();
    return allowedHosts.contains(h) || allowedHosts.contains('$h:$port');
  }

  /// Why the page making [request] may not use the relay, or null if it may.
  ///
  /// A browser always says which page opened a WebSocket (`Origin`), and
  /// that page has to be this one (or listed), so other sites can't use the
  /// relay from a visitor's browser. Only non-browser clients send no
  /// `Origin` at all; `Origin: null` (a sandboxed iframe, a local file) is a
  /// browser page that is never allowed.
  ///
  /// With contexts loaded, the `Host` the page was loaded from must also be
  /// localhost or an IP address (or listed): a DNS-rebinding page has a
  /// matching `Origin`, but its own name. That check uses `Host` alone: a
  /// browser won't let a script set it, but a same-origin `fetch` may set
  /// `X-Forwarded-Host`. [webSocket] is false for plain requests, which a
  /// browser sends without `Origin` from the same page.
  String? pageRefusal(Request request, {required bool webSocket}) {
    final host = (request.headers['host'] ?? '').trim().toLowerCase();
    final forwardedHost = _forwardedHost(request);
    final origin = request.headers['origin']?.trim().toLowerCase();
    final hasOrigin = origin != null && origin.isNotEmpty;
    if (hasOrigin && allowedOrigins.contains(origin)) return null;
    if (hasOrigin &&
        !_sameOrigin(origin, host) &&
        !(forwardedHost != null && _sameOrigin(origin, forwardedHost))) {
      if (!_isOrigin(origin)) {
        return 'this page has no origin of its own (a sandboxed frame or a '
            'local file), so it cannot use the relay';
      }
      final served = forwardedHost ?? host;
      return 'this page (${_printable(origin)}) is not the one the relay '
          'serves (${_printable(served)}); if a proxy changes the address, '
          'add ${_printable(origin)} to NATS_UI_ALLOWED_ORIGINS';
    }
    if (contexts.isEmpty || (webSocket && !hasOrigin)) return null;
    final name = _hostName(host);
    if (name == 'localhost' ||
        name.endsWith('.localhost') ||
        InternetAddress.tryParse(name) != null ||
        allowedOrigins.any((o) => Uri.tryParse(o)?.host == name)) {
      return null;
    }
    // Without an Origin, the scheme the browser used: a proxy's, else ours.
    final scheme =
        request.headers['x-forwarded-proto']?.split(',').first.trim();
    final suggestion = hasOrigin
        ? origin
        : '${scheme == null || scheme.isEmpty ? request.requestedUri.scheme : scheme}://$host';
    return 'contexts can only be used from localhost or an IP address unless '
        'the page is listed: add ${_printable(suggestion)} to '
        'NATS_UI_ALLOWED_ORIGINS';
  }
}

/// A proxy's `X-Forwarded-Host`: the address the browser used when a proxy
/// changed `Host`. Only good for telling whether an `Origin` is this page's
/// own, never for trusting the page, since a same-origin script can set it.
String? _forwardedHost(Request request) {
  final value = request.headers['x-forwarded-host']?.split(',').first.trim();
  return value == null || value.isEmpty ? null : value.toLowerCase();
}

/// The name part of a `Host` value: `[::1]:8080` is `::1`.
String _hostName(String host) {
  if (host.startsWith('[')) {
    final end = host.indexOf(']');
    return end < 0 ? host : host.substring(1, end);
  }
  final colon = host.lastIndexOf(':');
  return colon < 0 ? host : host.substring(0, colon);
}

/// Whether [origin] is the page at [host]. Browsers leave a scheme's
/// default port out of both.
bool _sameOrigin(String origin, String host) {
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.host.isEmpty || host.isEmpty) return false;
  final name = _hostName(host);
  final rest =
      host.substring(host.startsWith('[') ? name.length + 2 : name.length);
  var port = rest.startsWith(':') ? rest.substring(1) : '';
  if (port == '80' || port == '443') port = '';
  final originPort = uri.hasPort ? '${uri.port}' : '';
  return uri.host == name && originPort == port;
}

/// [value] made safe for a log line or a `-ERR`: no control characters
/// (no forged log lines) or quotes (which end the `-ERR` text), and short.
String _printable(String value) {
  final cleaned = value.replaceAll(RegExp(r"[\x00-\x1f\x7f']"), '?');
  return cleaned.length > 100 ? '${cleaned.substring(0, 100)}...' : cleaned;
}

/// Who is connecting, for the log: a proxy's `X-Forwarded-For` (as given),
/// else the peer address.
String _clientAddress(Request request) {
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    return _printable(forwarded.split(',').first.trim());
  }
  final info = request.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
}

/// The whole server: the relay and contexts endpoints plus the static web
/// build in [webRoot].
Handler createHandler({
  required String webRoot,
  RelayConfig? relay,
  void Function(String message) log = print,
}) {
  final config = relay ?? RelayConfig();
  final staticHandler =
      createStaticHandler(webRoot, defaultDocument: 'index.html');
  return (Request request) {
    switch (request.url.path) {
      case relayPath:
        return _relayHandler(request, config, log);
      case contextsPath:
        return _contextsHandler(request, config, log);
    }
    return staticHandler(request);
  };
}

Response _contextsHandler(
    Request request, RelayConfig config, void Function(String) log) {
  const headers = {
    'content-type': 'application/json',
    'cache-control': 'no-store',
  };
  if (!config.enabled) return Response.ok('[]', headers: headers);
  final refusal = config.pageRefusal(request, webSocket: false);
  if (refusal != null) {
    log('contexts refused (from ${_clientAddress(request)}): $refusal');
    return Response.forbidden(jsonEncode({'error': refusal}), headers: headers);
  }
  return Response.ok(jsonEncode(config.contexts.toPublicJson()),
      headers: headers);
}

FutureOr<Response> _relayHandler(
    Request request, RelayConfig config, void Function(String) log) {
  final query = request.url.queryParameters;
  final refusal = config.pageRefusal(request, webSocket: true);
  final client = _clientAddress(request);
  return webSocketHandler((WebSocketChannel ws, String? _) {
    _Relay(ws, config, log,
            client: client,
            pageRefusal: refusal,
            contextName: query['context']?.trim(),
            host: query['host']?.trim() ?? '',
            port: int.tryParse(query['port'] ?? ''))
        .start();
  }, pingInterval: config.pingInterval)(request);
}

/// Why a connection attempt failed, as told to the browser.
class _Refusal implements Exception {
  _Refusal(this.reason);
  final String reason;
}

/// One browser WebSocket paired with one connection to a NATS server.
class _Relay {
  _Relay(this.ws, this.config, this.log,
      {required this.client,
      this.pageRefusal,
      this.contextName,
      required this.host,
      this.port});

  final WebSocketChannel ws;
  final RelayConfig config;
  final void Function(String) log;

  /// The browser's address, for the log.
  final String client;

  /// Set when the page may not use the relay at all.
  final String? pageRefusal;
  final String? contextName;
  final String host;
  final int? port;

  _ServerSide? _server;
  late final _ConnectRewriter _rewriter;
  bool _closed = false;
  String _target = '';

  Future<void> start() async {
    if (!config.enabled) {
      return _refuse('nats:// is turned off on this server '
          '(NATS_TCP_RELAY=off). Use ws:// instead');
    }
    if (pageRefusal != null) return _refuse(pageRefusal!);

    final NatsContext? context;
    final List<ContextServer> servers;
    var auth = const ContextAuth();
    final name = _printable(contextName ?? '');
    if (name.isNotEmpty) {
      context = config.contexts.byName(contextName!);
      if (context == null) {
        return _refuse('there is no context named "$name"');
      }
      if (context.error != null) {
        return _refuse('context "$name" is unusable: ${context.error}');
      }
      // Read now rather than at startup, so rotated credentials are used.
      try {
        auth = context.resolveAuth();
      } on ContextError catch (e) {
        if (e.detail != null) log('context "$name": ${e.detail}');
        return _refuse('context "$name" is unusable: ${e.message}');
      }
      servers = context.servers;
    } else {
      context = null;
      final port = this.port;
      if (host.isEmpty || port == null || port < 1 || port > 65535) {
        return _refuse('a host and a port between 1 and 65535 are required');
      }
      if (!config.allows(host, port)) {
        return _refuse(
            '${_printable(host)}:$port is not in NATS_TCP_ALLOWED_HOSTS');
      }
      servers = [ContextServer(host, port)];
    }

    // Hold what the browser sends until a server is connected (it normally
    // waits for INFO first), and tear everything down when it goes away.
    final pending = <List<int>>[];
    var pendingBytes = 0;
    _rewriter = _ConnectRewriter(auth);
    ws.stream.listen((dynamic data) {
      if (_closed) return;
      final bytes = data is String ? utf8.encode(data) : data as List<int>;
      final server = _server;
      if (server != null) return _toServer(server, bytes);
      pendingBytes += bytes.length;
      if (pendingBytes > _maxBrowserBuffer) {
        return _refuse('the browser sent too much before the server answered');
      }
      pending.add(bytes);
    }, onDone: _close, onError: (Object _) => _close());

    // A context can name several servers (a cluster): use the first that
    // answers.
    _Refusal? last;
    for (final server in servers) {
      if (_closed) return;
      try {
        final side = await _open(server, context);
        if (_closed) {
          side.destroy();
          return;
        }
        _server = side;
        _target = '${_printable(server.host)}:${server.port}';
        log('relay open (from $client): '
            '${context == null ? '' : 'context "$name" -> '}'
            '$_target${side.tls ? ' (TLS)' : ''}');
        _rewriter.nonce = side.nonce;
        ws.sink.add(side.greeting);
        side.forward(ws.sink.add, _close);
        for (final bytes in pending) {
          _toServer(side, bytes);
        }
        pending.clear();
        return;
      } on _Refusal catch (e) {
        last = e;
      }
    }
    _refuse(last?.reason ?? 'no server to connect to');
  }

  void _toServer(_ServerSide server, List<int> bytes) {
    if (_closed) return;
    final List<int> out;
    try {
      out = _rewriter.process(bytes);
    } on _Refusal catch (e) {
      return _refuse(e.reason);
    }
    if (out.isNotEmpty) server.socket.add(out);
  }

  /// Connects to [server], reads its INFO, and does TLS when the server asks
  /// for it, the URL is `tls://`, or the context names TLS files.
  Future<_ServerSide> _open(ContextServer server, NatsContext? context) async {
    final target = '${_printable(server.host)}:${server.port}';
    final tlsFirst = context?.tlsFirst ?? false;
    // Only built when TLS is used: most plain connections never need it.
    SecurityContext security() {
      try {
        return context?.securityContext() ??
            SecurityContext(withTrustedRoots: true);
      } catch (e) {
        log('context "${context?.name}": $e');
        throw _Refusal('the TLS files of the context cannot be loaded');
      }
    }

    Socket socket;
    try {
      socket = tlsFirst
          ? await SecureSocket.connect(server.host, server.port,
              context: security(), timeout: config.connectTimeout)
          : await Socket.connect(server.host, server.port,
              timeout: config.connectTimeout);
    } on _Refusal {
      rethrow;
    } on HandshakeException catch (e) {
      throw _Refusal('TLS with $target failed (${e.message})');
    } on TlsException catch (e) {
      throw _Refusal('TLS with $target failed (${e.message})');
    } catch (e) {
      throw _Refusal('cannot reach $target (${_describe(e)})');
    }

    final side = _ServerSide(socket, tls: tlsFirst);
    final Uint8List greeting;
    try {
      greeting = await side.greetingWithin(config.infoTimeout, target);
    } on _Refusal {
      side.destroy();
      rethrow;
    }
    final lineEnd = greeting.indexOf(0x0A);
    final line =
        utf8.decode(greeting.sublist(0, lineEnd), allowMalformed: true);
    if (!line.startsWith('INFO ')) {
      side.destroy();
      throw _Refusal('$target did not answer like a NATS server');
    }
    final Map<String, dynamic> info;
    try {
      info = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
    } catch (_) {
      side.destroy();
      throw _Refusal('$target sent an INFO that is not valid JSON');
    }
    side.nonce = info['nonce'] as String?;

    final wantsTls = info['tls_required'] == true ||
        server.tls ||
        (context?.usesTls ?? false);
    if (tlsFirst || !wantsTls) return side;

    // Upgrade in place, the way nats-server expects: INFO in the clear, then
    // the TLS handshake on the same socket. A server waiting for the
    // handshake sends nothing after INFO.
    side.detach();
    final SecurityContext securityContext;
    try {
      securityContext = security();
    } on _Refusal {
      socket.destroy();
      rethrow;
    }
    try {
      final secure = await SecureSocket.secure(socket,
              host: server.host, context: securityContext)
          .timeout(config.connectTimeout);
      return _ServerSide(secure, tls: true, greeting: greeting)
        ..nonce = side.nonce;
    } on TimeoutException {
      socket.destroy();
      throw _Refusal('TLS with $target timed out');
    } on HandshakeException catch (e) {
      socket.destroy();
      throw _Refusal('TLS with $target failed (${e.message})');
    } on TlsException catch (e) {
      socket.destroy();
      throw _Refusal('TLS with $target failed (${e.message})');
    } on SocketException catch (e) {
      socket.destroy();
      throw _Refusal('TLS with $target failed (${e.message})');
    }
  }

  /// Tells the browser why, as a NATS `-ERR` its client will surface, and
  /// closes both sides.
  void _refuse(String reason) {
    if (_closed) return;
    // A quote would end the -ERR text early.
    final text =
        reason.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '?').replaceAll("'", '"');
    log('relay refused (from $client): $text');
    ws.sink.add(utf8.encode("-ERR '$relayErrorMarker $text'\r\n"));
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (_server != null) log('relay closed (from $client): $_target');
    _server?.destroy();
    ws.sink.close();
  }

  static String _describe(Object e) =>
      e is SocketException ? e.message : e.toString();
}

/// The server end of a relay: collects the INFO greeting, then forwards
/// everything to the browser.
class _ServerSide {
  _ServerSide(this.socket, {required this.tls, Uint8List? greeting}) {
    if (greeting != null) {
      _greetingBytes = greeting;
      _greeting.complete(greeting);
    }
    _subscription = socket.listen(_onData,
        onDone: _onDone, onError: (Object _) => _onDone());
  }

  final Socket socket;
  final bool tls;
  String? nonce;

  final _greeting = Completer<Uint8List>();
  final _buffer = BytesBuilder(copy: false);
  final _early = <Uint8List>[];
  late final StreamSubscription<Uint8List> _subscription;
  void Function(Uint8List)? _onForward;
  void Function()? _onClosed;
  bool _detached = false;
  bool _done = false;

  Uint8List? _greetingBytes;

  /// The INFO line (and anything after it); valid once [greetingWithin]
  /// completed, or when passed to the constructor.
  Uint8List get greeting => _greetingBytes!;

  Future<Uint8List> greetingWithin(Duration timeout, String target) async {
    try {
      return _greetingBytes = await _greeting.future.timeout(timeout);
    } on TimeoutException {
      throw _Refusal('$target did not answer like a NATS server');
    }
  }

  void _onData(Uint8List data) {
    if (_detached) return;
    if (!_greeting.isCompleted) {
      _buffer.add(data);
      final bytes = _buffer.toBytes();
      if (bytes.contains(0x0A)) {
        _greeting.complete(bytes);
      } else if (bytes.length > 64 * 1024) {
        _greeting.completeError(_Refusal('the server did not answer like a '
            'NATS server'));
      }
      return;
    }
    final forward = _onForward;
    forward == null ? _early.add(data) : forward(data);
  }

  void _onDone() {
    if (_detached || _done) return;
    _done = true;
    if (!_greeting.isCompleted) {
      _greeting.completeError(
          _Refusal('the server closed the connection before sending INFO'));
    }
    _onClosed?.call();
  }

  /// Sends everything from now on to [onData], and calls [onClosed] when the
  /// server goes away.
  void forward(void Function(Uint8List) onData, void Function() onClosed) {
    for (final data in _early) {
      onData(data);
    }
    _early.clear();
    _onForward = onData;
    _onClosed = onClosed;
    if (_done) onClosed();
  }

  /// Stops listening before the socket is handed to [SecureSocket.secure].
  void detach() => _detached = true;

  void destroy() {
    _detached = true;
    _subscription.cancel();
    socket.destroy();
  }
}

/// Puts a context's credentials into the browser's first `CONNECT`, which
/// the relay sees before the server does. Everything else passes through.
class _ConnectRewriter {
  _ConnectRewriter(this.auth);

  final ContextAuth auth;
  String? nonce;
  bool _done = false;
  final _buffer = BytesBuilder(copy: false);

  /// What to send on for [bytes]. Throws a [_Refusal] for a first line that
  /// is too long or not UTF-8.
  List<int> process(List<int> bytes) {
    if (_done || auth.isEmpty) return bytes;
    _buffer.add(bytes);
    final data = _buffer.toBytes();
    final lineEnd = data.indexOf(0x0A);
    if (lineEnd < 0) {
      if (data.length > _maxBrowserBuffer) {
        throw _Refusal('the CONNECT from the browser is too long');
      }
      return const [];
    }
    _done = true;
    final String line;
    try {
      line = utf8.decode(data.sublist(0, lineEnd)).trimRight();
    } on FormatException {
      throw _Refusal('the CONNECT from the browser is not valid UTF-8');
    }
    final rest = data.sublist(lineEnd + 1);
    if (!line.toUpperCase().startsWith('CONNECT ')) return data;
    Map<String, dynamic> options;
    try {
      options = jsonDecode(line.substring(8)) as Map<String, dynamic>;
    } catch (_) {
      return data;
    }
    final rewritten = auth.apply(options, nonce);
    return [...utf8.encode('CONNECT ${jsonEncode(rewritten)}\r\n'), ...rest];
  }
}
