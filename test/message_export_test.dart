import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/message_export.dart';

void main() {
  group('encode/decode round trip', () {
    test('all fields present round-trip exactly', () {
      final capturedAt = DateTime.utc(2026, 7, 15, 12, 30);
      final message = ExportedMessage(
        subject: 'orders.new',
        payload: Uint8List.fromList([1, 2, 3, 4]),
        headers: {'Trace-Id': 'abc123'},
        capturedAt: capturedAt,
      );

      final line = encodeExportedMessageLine(message);
      final decoded = decodeExportedMessageLine(line);

      expect(decoded.subject, 'orders.new');
      expect(decoded.payload, [1, 2, 3, 4]);
      expect(decoded.headers, {'Trace-Id': 'abc123'});
      expect(decoded.capturedAt, capturedAt);
    });

    test('null headers/capturedAt are omitted then decode back to null', () {
      final message = ExportedMessage(
        subject: 'orders.new',
        payload: Uint8List.fromList([9, 9]),
      );

      final line = encodeExportedMessageLine(message);
      expect(line.contains('headers'), isFalse);
      expect(line.contains('capturedAt'), isFalse);

      final decoded = decodeExportedMessageLine(line);
      expect(decoded.headers, isNull);
      expect(decoded.capturedAt, isNull);
    });
  });

  test('binary payload survives round trip byte-for-byte', () {
    // Invalid-UTF-8 byte sequences that would be mangled by any text-based
    // round trip -- the regression test proving base64 was the right call.
    final bytes = Uint8List.fromList([0xFF, 0xFE, 0x00, 0x80, 0xC0, 0x00]);
    final message = ExportedMessage(subject: 'raw.bytes', payload: bytes);

    final line = encodeExportedMessageLine(message);
    final decoded = decodeExportedMessageLine(line);

    expect(decoded.payload, bytes);
  });

  test('parsing empty content yields no messages and no errors', () {
    final result = parseExportedMessagesNdjson('');
    expect(result.messages, isEmpty);
    expect(result.hasErrors, isFalse);
  });

  test('blank lines are skipped without becoming errors', () {
    final message = ExportedMessage(
      subject: 'a.b',
      payload: Uint8List.fromList([1]),
    );
    final content = '\n${encodeExportedMessageLine(message)}\n   \n';

    final result = parseExportedMessagesNdjson(content);
    expect(result.messages, hasLength(1));
    expect(result.hasErrors, isFalse);
  });

  test(
      'a malformed line is captured in errors with correct 1-based line '
      'number while surrounding valid lines still parse', () {
    final first =
        ExportedMessage(subject: 'a', payload: Uint8List.fromList([1]));
    final second =
        ExportedMessage(subject: 'b', payload: Uint8List.fromList([2]));
    final content = [
      encodeExportedMessageLine(first),
      'not valid json at all',
      encodeExportedMessageLine(second),
    ].join('\n');

    final result = parseExportedMessagesNdjson(content);

    expect(result.messages, hasLength(2));
    expect(result.messages[0].subject, 'a');
    expect(result.messages[1].subject, 'b');
    expect(result.hasErrors, isTrue);
    expect(result.errors, hasLength(1));
    expect(result.errors.single.lineNumber, 2);
    expect(result.errors.single.rawLine, 'not valid json at all');
  });

  test('multi-message round trip preserves order', () {
    final messages = List.generate(
      5,
      (i) => ExportedMessage(
        subject: 'subj.$i',
        payload: Uint8List.fromList([i]),
      ),
    );

    final encoded = encodeExportedMessagesNdjson(messages);
    expect(encoded.endsWith('\n'), isTrue);

    final result = parseExportedMessagesNdjson(encoded);
    expect(result.messages.map((m) => m.subject).toList(),
        messages.map((m) => m.subject).toList());
  });

  test('exportedMessageFromNatsMessage bridges a real dart_nats Message', () {
    final natsMessage = Message<dynamic>(
      'orders.new',
      1,
      Uint8List.fromList([5, 6, 7]),
      Client(),
      header: Header(headers: {'X-Test': 'yes'}),
    );
    final capturedAt = DateTime.utc(2026, 1, 1);

    final exported =
        exportedMessageFromNatsMessage(natsMessage, capturedAt: capturedAt);

    expect(exported.subject, 'orders.new');
    expect(exported.payload, [5, 6, 7]);
    expect(exported.headers, {'X-Test': 'yes'});
    expect(exported.capturedAt, capturedAt);
  });

  test('exportedMessageFromNatsMessage omits empty headers', () {
    final natsMessage = Message<dynamic>(
      'orders.new',
      1,
      Uint8List.fromList([1]),
      Client(),
    );

    final exported = exportedMessageFromNatsMessage(natsMessage);

    expect(exported.headers, isNull);
    expect(exported.capturedAt, isNull);
  });
}
