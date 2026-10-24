import 'dart:convert';

import 'package:dart_nats/dart_nats.dart';
import 'package:http/http.dart' as http;

/// True only in the Docker image's web build (`--dart-define=NATS_TCP_RELAY=true`
/// in the Dockerfile), whose server also relays WebSocket connections to
/// NATS servers over plain TCP (`docker/tcp_relay/`). Lets the browser offer
/// `nats://`, which it otherwise can't, since browsers have no TCP sockets.
const bool tcpRelayAvailable = bool.fromEnvironment('NATS_TCP_RELAY');

/// The relay endpoint's path, relative to the page. Must match `relayPath` in
/// `docker/tcp_relay/lib/relay.dart`.
const String tcpRelayPath = 'nats-tcp';

/// The path of the relay's list of NATS CLI contexts, relative to the page.
/// Must match `contextsPath` in `docker/tcp_relay/lib/relay.dart`.
const String tcpRelayContextsPath = 'contexts';

/// Prefix of every `-ERR` the relay sends when it refuses a target. Must
/// match `relayErrorMarker` in `docker/tcp_relay/lib/relay.dart`.
const String tcpRelayErrorMarker = 'NATS TCP relay:';

/// The WebSocket URL that relays to the NATS server at [host]:[port]: same
/// origin as the page at [pageBase], `wss` when the page is served over
/// https, and resolved relative to the page so a reverse proxy serving the
/// app under a sub-path still reaches the relay.
Uri tcpRelayUri(Uri pageBase, String host, String port) {
  final endpoint = pageBase.resolve(tcpRelayPath);
  // A bracketed IPv6 literal is URL syntax; the relay wants the bare address.
  final bareHost = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  return endpoint.replace(
    scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
    queryParameters: {'host': bareHost, 'port': port},
  );
}

/// The reason the relay gave for refusing a connection, or null when [error]
/// didn't come from the relay.
String? tcpRelayRefusalReason(Object error) {
  if (error is! NatsException) return null;
  final message = error.message ?? '';
  final start = message.indexOf(tcpRelayErrorMarker);
  if (start < 0) return null;
  var reason = message.substring(start + tcpRelayErrorMarker.length).trim();
  if (reason.endsWith("'")) reason = reason.substring(0, reason.length - 1);
  return reason;
}

/// The relay endpoint that connects as the context named [name]: the relay
/// supplies the server, credentials and TLS settings, so the browser never
/// sees them.
Uri tcpRelayContextUri(Uri pageBase, String name) {
  final endpoint = pageBase.resolve(tcpRelayPath);
  return endpoint.replace(
    scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
    queryParameters: {'context': name},
  );
}

/// A NATS CLI context the Docker image's relay can connect as. Only what's
/// safe to show: no credentials or file paths.
class RelayContext {
  const RelayContext({
    required this.name,
    this.description = '',
    required this.server,
    this.selected = false,
    this.error,
  });

  final String name;
  final String description;

  /// The context's first server, e.g. `tls://connect.ngs.global:4222`.
  final String server;

  /// Whether the container chose this context to preselect.
  final bool selected;

  /// Why the relay can't use this context (e.g. a missing file), or null.
  final String? error;

  Uri? get _serverUri => Uri.tryParse(server);

  /// The server's host and port, to show in the Host and Port fields.
  String get host => _serverUri?.host ?? '';
  String get port {
    final uri = _serverUri;
    return uri != null && uri.hasPort ? '${uri.port}' : '4222';
  }

  static RelayContext fromJson(Map<String, dynamic> json) => RelayContext(
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        server: (json['server'] as String?) ?? '',
        selected: json['selected'] == true,
        error: json['error'] as String?,
      );
}

/// Parses the relay's context list; tolerates anything malformed by
/// returning no contexts.
List<RelayContext> parseRelayContexts(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map<String, dynamic> && entry['name'] is String)
          RelayContext.fromJson(entry),
    ];
  } on FormatException {
    return const [];
  }
}

/// Fetches the contexts the relay serving the page at [pageBase] can connect
/// as. Any failure (an older image, a network error) just means none.
/// [refusal] is set when the relay won't list them to this page (it isn't
/// opened from an address the container allows), saying why.
Future<({List<RelayContext> contexts, String? refusal})> fetchRelayContexts(
    Uri pageBase,
    {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(pageBase.resolve(tcpRelayContextsPath))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 403) {
      return (contexts: const <RelayContext>[], refusal: _refusal(response));
    }
    if (response.statusCode != 200) {
      return (contexts: const <RelayContext>[], refusal: null);
    }
    return (contexts: parseRelayContexts(response.body), refusal: null);
  } catch (_) {
    return (contexts: const <RelayContext>[], refusal: null);
  } finally {
    if (client == null) c.close();
  }
}

String? _refusal(http.Response response) {
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['error'] is String) {
      return decoded['error'] as String;
    }
  } on FormatException {
    // Not the relay's own refusal
  }
  return null;
}
