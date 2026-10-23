import 'package:dart_nats/dart_nats.dart';

/// True only in the Docker image's web build (`--dart-define=NATS_TCP_RELAY=true`
/// in the Dockerfile), whose server also relays WebSocket connections to
/// NATS servers over plain TCP (`docker/tcp_relay/`). Lets the browser offer
/// `nats://`, which it otherwise can't, since browsers have no TCP sockets.
const bool tcpRelayAvailable = bool.fromEnvironment('NATS_TCP_RELAY');

/// The relay endpoint's path, relative to the page. Must match `relayPath` in
/// `docker/tcp_relay/lib/relay.dart`.
const String tcpRelayPath = 'nats-tcp';

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
