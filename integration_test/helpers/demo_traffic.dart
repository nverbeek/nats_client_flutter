import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_nats/dart_nats.dart' hide Consumer;

/// Plausible message traffic from a handful of named clients, for the
/// Server tab's screenshot (`screenshot_tour_test.dart`): the connections
/// list shows real-looking service names, and the throughput chart has
/// some shape to it instead of a flat line.
///
/// Two services publish at a rate that rises and falls (a slow wave plus a
/// short burst every so often), and the others subscribe, several to the
/// same subjects, so each message fans out and "out" sits well above "in".
class DemoTraffic {
  DemoTraffic({this.url = 'nats://127.0.0.1:4222'});

  final String url;
  final List<Client> _clients = [];
  Timer? _timer;
  final _random = math.Random(7);

  /// (connection name, subjects it subscribes to)
  static const _subscribers = [
    ('billing-worker', ['demo.orders.>']),
    ('inventory-sync', ['demo.orders.created', 'demo.orders.cancelled']),
    ('shipping-tracker', ['demo.orders.shipped']),
    ('metrics-scraper', ['demo.telemetry.>']),
    ('audit-logger', ['demo.>']),
  ];

  Future<Client> _connect(String name) async {
    final client = Client();
    await client.connect(Uri.parse(url),
        connectOption: ConnectOption(name: name, lang: 'dart'), retry: false);
    _clients.add(client);
    return client;
  }

  Future<void> start() async {
    for (final (name, subjects) in _subscribers) {
      final client = await _connect(name);
      for (final subject in subjects) {
        // Drained, so the messages don't pile up in the stream.
        client.sub(subject).stream.listen((_) {});
      }
    }
    final orders = await _connect('orders-api');
    final telemetry = await _connect('telemetry-ingest');

    const tick = Duration(milliseconds: 100);
    final started = DateTime.now();
    _timer = Timer.periodic(tick, (_) {
      final seconds =
          DateTime.now().difference(started).inMilliseconds / 1000.0;
      // Messages per second: a 45 s wave around 120, plus an 8 s burst
      // every 35 s, so the two-minute chart shows a few distinct shapes.
      final wave = 120 + 70 * math.sin(2 * math.pi * seconds / 45);
      final burst = (seconds % 35) < 8 ? 160 : 0;
      final perTick =
          ((wave + burst) / 10 * (0.85 + _random.nextDouble() * 0.3)).round();
      for (var i = 0; i < perTick; i++) {
        if (_random.nextDouble() < 0.6) {
          final kind = const [
            'created',
            'created',
            'shipped',
            'cancelled'
          ][_random.nextInt(4)];
          orders.pubString(
              'demo.orders.$kind',
              jsonEncode({
                'order_id': 'ORD-${100000 + _random.nextInt(900000)}',
                'status': kind,
                'items': _random.nextInt(6) + 1,
                'total': (_random.nextDouble() * 400).toStringAsFixed(2),
              }));
        } else {
          final sensor = 'sensor-${_random.nextInt(24)}';
          telemetry.pubString(
              'demo.telemetry.$sensor',
              jsonEncode({
                'sensor': sensor,
                'temp_c': (18 + _random.nextDouble() * 9).toStringAsFixed(1),
                'humidity': _random.nextInt(40) + 30,
              }));
        }
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    for (final client in _clients) {
      await client.forceClose();
    }
    _clients.clear();
  }
}
