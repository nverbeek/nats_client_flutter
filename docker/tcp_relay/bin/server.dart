import 'dart:io';

import 'package:nats_tcp_relay/allowlist.dart';
import 'package:nats_tcp_relay/context.dart';
import 'package:nats_tcp_relay/relay.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Entry point of the Docker image. Configured through the environment:
///
/// - `PORT`: port to listen on (default 8080), on IPv6 and IPv4.
/// - `WEB_ROOT`: directory holding the Flutter web build (default /app/web).
/// - `NATS_TCP_RELAY`: `off` makes the relay refuse every connection, so
///   only ws:// works. The app still lists nats://, and shows the refusal.
/// - `NATS_TCP_ALLOWED_HOSTS`: comma-separated entries the relay may connect
///   to: a host, a `*.domain` wildcard or a CIDR range, each optionally with
///   `:port`. Unset allows any NATS server. Connecting as a context is always
///   allowed. Also limits the `nats-monitor` proxy, where an entry with a
///   port has to name the monitoring port.
/// - `NATS_UI_ALLOWED_ORIGINS`: comma-separated origins
///   (`https://nats-ui.example.com`) of pages that may use the relay besides
///   its own address. Needed with contexts when the page isn't opened from
///   localhost or an IP address, or behind a proxy that changes `Host`.
/// - `NATS_CONTEXTS`: directory of NATS CLI context files (default
///   /nats-contexts). Each `*.json` is a context the app can connect as.
///   Read again when the directory changes, so contexts can be added while
///   the server runs.
/// - `NATS_URL` (with `NATS_USER`, `NATS_PASSWORD`, `NATS_CREDS`,
///   `NATS_NKEY`, `NATS_CERT`, `NATS_KEY`, `NATS_CA`, as the nats CLI reads
///   them, plus this image's `NATS_TOKEN`, `NATS_JWT` and `NATS_SEED`): one
///   more context, named `default`.
/// - `NATS_CONTEXT`: the context the app preselects (else `context.txt`, or
///   the only context).
Future<void> main() async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final webRoot = env['WEB_ROOT'] ?? '/app/web';
  final relayValue = (env['NATS_TCP_RELAY'] ?? '').trim().toLowerCase();
  final enabled = !const {'off', 'false', '0', 'no'}.contains(relayValue);
  final contextsDir = env['NATS_CONTEXTS'] ?? '/nats-contexts';
  final directory = ContextDirectory(
    dir: contextsDir,
    env: env,
    onChange: (previous, current) {
      print('Contexts in $contextsDir changed');
      _describeContexts(current, enabled, warnPublic: previous.isEmpty);
    },
  );
  final relay = RelayConfig(
    enabled: enabled,
    allowedHosts: RelayConfig.parseAllowedHosts(env['NATS_TCP_ALLOWED_HOSTS']),
    allowedOrigins:
        RelayConfig.parseAllowedOrigins(env['NATS_UI_ALLOWED_ORIGINS']),
    loadContexts: () => directory.current,
  );

  final handler = createHandler(webRoot: webRoot, relay: relay);
  HttpServer server;
  try {
    // Both IPv6 and IPv4, for IPv6-only clusters.
    server = await shelf_io.serve(handler, InternetAddress.anyIPv6, port);
  } on SocketException {
    // A container with IPv6 turned off.
    server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }
  print('Serving $webRoot on port ${server.port}; '
      'TCP relay ${relay.enabled ? 'on' : 'off'}'
      '${relay.allowedHosts.isEmpty ? '' : ', allowed: ${relay.allowedHosts.join(', ')}'}'
      '${relay.allowedOrigins.isEmpty ? '' : ', allowed origins: ${relay.allowedOrigins.join(', ')}'}');
  _describeContexts(directory.current, enabled, warnPublic: true);
  for (final entry
      in RelayConfig.invalidOrigins(env['NATS_UI_ALLOWED_ORIGINS'])) {
    print('Warning: ignoring "$entry" in NATS_UI_ALLOWED_ORIGINS: an origin '
        'is a scheme and host, such as https://nats-ui.example.com');
  }
  for (final entry in HostAllowlist.invalid(env['NATS_TCP_ALLOWED_HOSTS'])) {
    print('Warning: "$entry" in NATS_TCP_ALLOWED_HOSTS allows nothing: an '
        'entry is a host, *.domain or CIDR range, optionally with :port');
  }

  // As PID 1 in a container nothing else handles these, so `docker stop`
  // would otherwise wait out its full timeout.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    if (Platform.isWindows && signal == ProcessSignal.sigterm) continue;
    signal.watch().listen((_) async {
      await server.close(force: true);
      exit(0);
    });
  }
}

/// Logs [contexts], and with [warnPublic] that anyone who can open the page
/// can use them.
void _describeContexts(ContextSet contexts, bool enabled,
    {required bool warnPublic}) {
  for (final c in contexts.contexts) {
    print(
        'Context "${c.name}"${c.name == contexts.selected ? ' (selected)' : ''}: '
        '${c.servers.join(', ')}${c.error == null ? '' : ' -- unusable'}');
  }
  if (warnPublic && !contexts.isEmpty && enabled) {
    print('Anyone who can open this page can connect as these contexts; '
        'keep it private, or put an authenticating proxy in front of it');
  }
  for (final warning in contexts.warnings) {
    print('Warning: $warning');
  }
}
