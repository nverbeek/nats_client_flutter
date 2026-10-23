import 'dart:io';

import 'package:nats_tcp_relay/relay.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Entry point of the Docker image. Configured through the environment:
///
/// - `PORT`: port to listen on (default 80).
/// - `WEB_ROOT`: directory holding the Flutter web build (default /app/web).
/// - `NATS_TCP_RELAY`: `off` makes the relay refuse every connection, so
///   only ws:// works. The app still lists nats://, and shows the refusal.
/// - `NATS_TCP_ALLOWED_HOSTS`: comma-separated `host` or `host:port` entries
///   the relay may connect to. Unset allows any NATS server.
Future<void> main() async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 80;
  final webRoot = env['WEB_ROOT'] ?? '/app/web';
  final relayValue = (env['NATS_TCP_RELAY'] ?? '').trim().toLowerCase();
  final relay = RelayConfig(
    enabled: !const {'off', 'false', '0', 'no'}.contains(relayValue),
    allowedHosts: RelayConfig.parseAllowedHosts(env['NATS_TCP_ALLOWED_HOSTS']),
  );

  final server = await shelf_io.serve(
      createHandler(webRoot: webRoot, relay: relay),
      InternetAddress.anyIPv4,
      port);
  print('Serving $webRoot on port ${server.port}; '
      'TCP relay ${relay.enabled ? 'on' : 'off'}'
      '${relay.allowedHosts.isEmpty ? '' : ', allowed: ${relay.allowedHosts.join(', ')}'}');

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
