import 'dart:convert';

/// One successfully-used connection target, persisted so the Host field's
/// dropdown can offer it again. Dedup identity is the (scheme, host, port)
/// triple; see [recordConnection].
class ConnectionHistoryEntry {
  final String scheme; // e.g. 'nats://'
  final String host; // e.g. '127.0.0.1'
  final String port; // e.g. '4222'

  const ConnectionHistoryEntry({
    required this.scheme,
    required this.host,
    required this.port,
  });

  /// Full URI shown in the dropdown rows, e.g. 'nats://127.0.0.1:4222'.
  String get fullUri => '$scheme$host:$port';

  bool sameTarget(ConnectionHistoryEntry other) =>
      scheme == other.scheme && host == other.host && port == other.port;

  Map<String, dynamic> _toJson() =>
      {'scheme': scheme, 'host': host, 'port': port};
}

/// Most recent connection targets are kept; older ones drop off the end.
const int maxConnectionHistory = 10;

/// JSON-encodes the connection history for storage under
/// [constants.prefConnectionHistory].
String encodeConnectionHistory(List<ConnectionHistoryEntry> history) =>
    jsonEncode(history.map((e) => e._toJson()).toList());

/// Decodes a history list previously written by [encodeConnectionHistory].
List<ConnectionHistoryEntry> decodeConnectionHistory(String json) {
  final decoded = jsonDecode(json) as List<dynamic>;
  return decoded.map((entry) {
    final map = entry as Map<String, dynamic>;
    return ConnectionHistoryEntry(
      scheme: map['scheme'] as String,
      host: map['host'] as String,
      port: map['port'] as String,
    );
  }).toList();
}

/// Returns a NEW list with the just-used target at the front, deduped by
/// (scheme, host, port) and capped at [maxConnectionHistory]. Pure -- the
/// caller persists + setStates the result.
List<ConnectionHistoryEntry> recordConnection(
  List<ConnectionHistoryEntry> current,
  String scheme,
  String host,
  String port,
) {
  final entry = ConnectionHistoryEntry(scheme: scheme, host: host, port: port);
  final next = <ConnectionHistoryEntry>[
    entry,
    ...current.where((e) => !e.sameTarget(entry)),
  ];
  return next.length > maxConnectionHistory
      ? next.sublist(0, maxConnectionHistory)
      : next;
}
