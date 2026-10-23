import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Smoke-tests a running image: the web build is served, and a nats://
/// connection relayed to a real NATS server completes a PING/PONG.
///
///     dart run tool/smoke.dart <image base url> <nats host> <nats port>
///     dart run tool/smoke.dart http://127.0.0.1:8080 127.0.0.1 4222
Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: smoke.dart <base url> <nats host> <nats port>');
    exit(64);
  }
  final base = Uri.parse(args[0]);

  final http = HttpClient();
  final request = await http.getUrl(base.resolve('/'));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  http.close();
  if (response.statusCode != 200 || !body.contains('flutter')) {
    throw StateError('GET / returned ${response.statusCode}, '
        'not the Flutter web build');
  }
  print('web build served');

  final relay = base.resolve('/nats-tcp').replace(
      scheme: 'ws', queryParameters: {'host': args[1], 'port': args[2]});
  final ws = WebSocketChannel.connect(relay);
  await ws.ready;
  final received = StringBuffer();
  final pong = Completer<void>();
  ws.stream.listen((dynamic data) {
    received.write(data is String ? data : utf8.decode(data as List<int>));
    final text = received.toString();
    if (text.startsWith('INFO ') && !text.contains('PING_SENT')) {
      received.write('PING_SENT');
      ws.sink.add(utf8.encode('CONNECT {"verbose":false}\r\nPING\r\n'));
    }
    if (text.contains('PONG') && !pong.isCompleted) pong.complete();
  }, onDone: () {
    if (!pong.isCompleted) {
      pong.completeError(StateError('relay closed: $received'));
    }
  });
  await pong.future.timeout(const Duration(seconds: 10));
  await ws.sink.close();
  print('relayed PING/PONG with $relay');
}
