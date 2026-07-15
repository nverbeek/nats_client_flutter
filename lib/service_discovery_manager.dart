import 'package:dart_nats/dart_nats.dart' hide Consumer;

/// Thin, testable wrapper around a connected [Client] for NATS Microservices
/// (ADR-32) discovery, mirroring the shape of `KvManager`/
/// `ObjectStoreManager`. Unlike those two, this has no JetStream dependency
/// and nothing to list up front — every call is itself a fan-out request
/// that only knows what's out there once replies trickle back in.
class ServiceDiscoveryManager {
  final Client client;

  ServiceDiscoveryManager(this.client);

  /// Discover every running service instance on the account by fanning a
  /// `$SRV.PING` request out and collecting whatever replies arrive within
  /// [timeout]. An empty result is the common case (no services running)
  /// and is not treated as an error.
  Future<List<PingResponse>> discover({
    Duration timeout = const Duration(milliseconds: 750),
  }) {
    return client.discoverServices(timeout: timeout);
  }

  /// Fetch endpoint/subject detail for one specific service instance.
  /// Returns `null` if that instance didn't reply within [timeout] (e.g. it
  /// stopped between the initial discovery and this follow-up call).
  Future<InfoResponse?> fetchInfo(
    String name,
    String id, {
    Duration timeout = const Duration(milliseconds: 750),
  }) async {
    final replies =
        await client.getServicesInfo(name: name, id: id, timeout: timeout);
    return replies.isEmpty ? null : replies.first;
  }

  /// Fetch request/error/latency stats for one specific service instance.
  /// Returns `null` if that instance didn't reply within [timeout].
  Future<StatsResponse?> fetchStats(
    String name,
    String id, {
    Duration timeout = const Duration(milliseconds: 750),
  }) async {
    final replies =
        await client.getServicesStats(name: name, id: id, timeout: timeout);
    return replies.isEmpty ? null : replies.first;
  }
}

/// Turns an error raised during service discovery into a short, user-facing
/// message. Pure function (no I/O), so it can be unit tested directly
/// without a live server.
String describeServiceDiscoveryError(Object error) {
  if (error is NatsException) {
    return error.message ?? 'Service discovery failed.';
  }
  return error.toString();
}

/// Formats a nanosecond duration (as reported by `$SRV.STATS`) into a short
/// human-readable string, picking whichever unit keeps the number readable.
/// Pure function, unit tested independently.
String formatNanos(int ns) {
  if (ns <= 0) return '0 ms';
  if (ns < 1000) return '$ns ns';
  if (ns < 1000000) return '${(ns / 1000).toStringAsFixed(1)} µs';
  if (ns < 1000000000) return '${(ns / 1000000).toStringAsFixed(1)} ms';
  return '${(ns / 1000000000).toStringAsFixed(2)} s';
}
