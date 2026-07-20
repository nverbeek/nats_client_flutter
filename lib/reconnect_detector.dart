import 'package:dart_nats/dart_nats.dart' hide Consumer;

/// Decides, from a stream of `dart_nats` [Status] events, when a *genuine
/// post-bounce reconnect* has just completed -- the connection had been up,
/// dropped, and has now come back.
///
/// Extracted from `main.dart`'s status listener as its own class purely so
/// this can be unit tested against `dart_nats`'s real transition sequence
/// without needing a live server to bounce. The original inline version
/// asked "was the immediately-preceding status `reconnecting`?", which is
/// never true: every transport in `Client._connectUri` emits
/// `infoHandshake` once the socket is up, *before* the INFO/ping exchange
/// completes and the status becomes `connected`. So the real sequence is
///
///   disconnected -> reconnecting -> infoHandshake -> connected
///
/// and the check never fired at all, leaving every dashboard's
/// post-reconnect recovery handler as dead code. Hence a latch: any sign of
/// connection loss arms it, and the next `connected` fires and disarms it,
/// regardless of how many intermediate handshake states pass in between.
class ReconnectDetector {
  bool _hasConnected = false;
  bool _armed = false;

  /// Whether a connection has been established at least once since the last
  /// [reset]. Until then, a drop can't be a *re*connect.
  bool get hasConnected => _hasConnected;

  /// Feeds one status event, returning `true` exactly once per genuine
  /// reconnect -- i.e. on the `connected` event that ends a drop. Returns
  /// `false` for the first successful connect of a session (there's nothing
  /// to recover from yet) and for every non-`connected` event.
  bool onStatus(Status status) {
    switch (status) {
      case Status.connected:
        final recovered = _armed;
        _armed = false;
        _hasConnected = true;
        return recovered;
      case Status.disconnected:
      case Status.closed:
      case Status.reconnecting:
        // Only arm once a connection has actually been up: the initial
        // connect loop also emits `reconnecting` for retry attempts past
        // the first, and a first-connect-after-retries has nothing for
        // listeners to recover.
        if (_hasConnected) _armed = true;
        return false;
      case Status.connecting:
      case Status.infoHandshake:
      case Status.tlsHandshake:
        return false;
    }
  }

  /// Clears all state, for a real session boundary: an explicit user
  /// Disconnect, or a fresh `natsConnect()` starting over with a new
  /// `Client`. Without this a reconnect could be reported across two
  /// unrelated connections.
  void reset() {
    _hasConnected = false;
    _armed = false;
  }
}
