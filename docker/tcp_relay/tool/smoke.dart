import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

/// Smoke-tests a running image: the web build is served, and a nats://
/// connection relayed to a real NATS server completes a PING/PONG, either to
/// a host and port or as one of the image's contexts (which the relay
/// authenticates as, so a PONG proves the server accepted its credentials).
///
///     dart run tool/smoke.dart <image base url> <nats host> <nats port>
///     dart run tool/smoke.dart <image base url> --context <name>
///     dart run tool/smoke.dart http://127.0.0.1:8080 127.0.0.1 4222
///
/// Under a path prefix, give the base URL with a trailing slash, e.g.
/// `http://localhost/nats/`.
///
/// `--origin <url>` connects as a page from that origin would, and
/// `--expect-refusal` passes only if the relay refuses the connection.
Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  String? origin;
  final originAt = args.indexOf('--origin');
  if (originAt >= 0 && originAt + 1 < args.length) {
    origin = args[originAt + 1];
    args.removeRange(originAt, originAt + 2);
  }
  final expectRefusal = args.remove('--expect-refusal');
  if (args.length != 3) {
    stderr.writeln('usage: smoke.dart <base url> <nats host> <nats port>\n'
        '       smoke.dart <base url> --context <name>\n'
        '  [--origin <url>] [--expect-refusal]');
    exit(64);
  }
  final base = Uri.parse(args[0]);
  final query = args[1] == '--context'
      ? {'context': args[2]}
      : {'host': args[1], 'port': args[2]};

  final http = HttpClient();
  final request = await http.getUrl(base.resolve('./'));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  http.close();
  if (response.statusCode != 200 || !body.contains('flutter')) {
    throw StateError('GET / returned ${response.statusCode}, '
        'not the Flutter web build');
  }
  // An absolute <base href> would send the page's requests outside a proxy's
  // path prefix; see web/index.html.
  if (body.contains('<base href="/')) {
    throw StateError('the page has an absolute <base href>, so it would '
        'break when served under a path prefix');
  }
  print('web build served');

  final relay =
      base.resolve('nats-tcp').replace(scheme: 'ws', queryParameters: query);
  final ws = IOWebSocketChannel.connect(relay,
      headers: {if (origin != null) 'Origin': origin});
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
    if (text.contains('-ERR') && !pong.isCompleted) {
      pong.completeError(StateError('refused: $received'));
    }
    if (text.contains('PONG') && !pong.isCompleted) pong.complete();
  }, onDone: () {
    if (!pong.isCompleted) {
      pong.completeError(StateError('relay closed: $received'));
    }
  });
  try {
    await pong.future.timeout(const Duration(seconds: 10));
  } on StateError catch (e) {
    if (!expectRefusal || !'$e'.contains('NATS TCP relay:')) rethrow;
    print('refused as expected: $received');
    return;
  } finally {
    await ws.sink.close();
  }
  if (expectRefusal) throw StateError('expected a refusal, got: $received');
  print('relayed PING/PONG with $relay');
}
