import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;

/// Message count past which Export shows a large-export warning -- it still
/// proceeds if confirmed (warn-and-proceed, not a silent hard cap).
const int largeExportWarningThreshold = 20000;

/// One captured message in the NDJSON export/replay format. Pure data --
/// no dependency on the app's live `Message` type beyond the one bridging
/// function [exportedMessageFromNatsMessage], so the rest of this module
/// stays testable without a `Client`.
class ExportedMessage {
  final String subject;
  final Uint8List payload;
  final Map<String, String>? headers;
  final DateTime? capturedAt;

  const ExportedMessage({
    required this.subject,
    required this.payload,
    this.headers,
    this.capturedAt,
  });
}

/// Encodes [message] as one NDJSON line:
/// `{"subject":"...","payload":"<base64>","headers":{...}?,"capturedAt":"<ISO-8601>"?}`.
/// Payload is base64 of the raw bytes -- lossless for binary payloads, unlike
/// the existing single-row Replay action which round-trips through text.
/// `headers`/`capturedAt` are omitted entirely (not null-valued) when absent.
String encodeExportedMessageLine(ExportedMessage message) {
  final json = <String, dynamic>{
    'subject': message.subject,
    'payload': base64Encode(message.payload),
  };
  if (message.headers != null && message.headers!.isNotEmpty) {
    json['headers'] = message.headers;
  }
  if (message.capturedAt != null) {
    json['capturedAt'] = message.capturedAt!.toIso8601String();
  }
  return jsonEncode(json);
}

/// Decodes one NDJSON line back into an [ExportedMessage]. Throws a
/// [FormatException] with a clear message on malformed input (missing or
/// wrong-typed `subject`/`payload`); `capturedAt` uses [DateTime.tryParse]
/// (null, not an error, if unparseable -- it's metadata only).
ExportedMessage decodeExportedMessageLine(String line) {
  final dynamic decoded = jsonDecode(line);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Line is not a JSON object.');
  }

  final subject = decoded['subject'];
  if (subject is! String) {
    throw const FormatException('Missing or non-string "subject".');
  }

  final payloadField = decoded['payload'];
  if (payloadField is! String) {
    throw const FormatException('Missing or non-string "payload".');
  }
  final Uint8List payload;
  try {
    payload = base64Decode(payloadField);
  } on FormatException {
    throw const FormatException('"payload" is not valid base64.');
  }

  Map<String, String>? headers;
  final headersField = decoded['headers'];
  if (headersField is Map) {
    headers = headersField.map((key, value) => MapEntry('$key', '$value'));
  }

  DateTime? capturedAt;
  final capturedAtField = decoded['capturedAt'];
  if (capturedAtField is String) {
    capturedAt = DateTime.tryParse(capturedAtField);
  }

  return ExportedMessage(
    subject: subject,
    payload: payload,
    headers: headers,
    capturedAt: capturedAt,
  );
}

/// One parse failure encountered while decoding an NDJSON file, keyed to
/// the 1-based line number it came from (counted over all raw lines,
/// including blanks, matching what a text editor's line numbers show).
class NdjsonParseError {
  final int lineNumber;
  final String rawLine;
  final String message;

  const NdjsonParseError({
    required this.lineNumber,
    required this.rawLine,
    required this.message,
  });
}

/// Result of parsing an NDJSON file: the messages that decoded
/// successfully, plus any per-line errors.
class NdjsonParseResult {
  final List<ExportedMessage> messages;
  final List<NdjsonParseError> errors;

  const NdjsonParseResult({required this.messages, required this.errors});

  bool get hasErrors => errors.isNotEmpty;
}

/// Parses NDJSON [content] (one JSON object per line). Blank lines are
/// skipped silently; every other line is decoded independently, so one
/// malformed line doesn't abort the parse -- matches this app's general
/// error-tolerant style (e.g. `decodeMessageText`'s `allowMalformed`).
NdjsonParseResult parseExportedMessagesNdjson(String content) {
  final messages = <ExportedMessage>[];
  final errors = <NdjsonParseError>[];

  final lines = const LineSplitter().convert(content);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    try {
      messages.add(decodeExportedMessageLine(line));
    } on FormatException catch (e) {
      errors.add(NdjsonParseError(
        lineNumber: i + 1,
        rawLine: line,
        message: e.message,
      ));
    }
  }

  return NdjsonParseResult(messages: messages, errors: errors);
}

/// Encodes [messages] as NDJSON, one line per message, with a trailing
/// newline.
String encodeExportedMessagesNdjson(List<ExportedMessage> messages) {
  final buffer = StringBuffer();
  for (final message in messages) {
    buffer.write(encodeExportedMessageLine(message));
    buffer.write('\n');
  }
  return buffer.toString();
}

/// Bridges the app's live `dart_nats` [Message] type into the pure
/// [ExportedMessage] shape -- the one function in this module that knows
/// about `Message`, keeping everything else testable without a `Client`.
ExportedMessage exportedMessageFromNatsMessage(
  Message<dynamic> message, {
  DateTime? capturedAt,
}) {
  final headers = message.header?.headers;
  return ExportedMessage(
    subject: message.subject ?? '',
    payload: message.byte,
    headers: (headers != null && headers.isNotEmpty) ? headers : null,
    capturedAt: capturedAt,
  );
}
