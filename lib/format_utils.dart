import 'dart:convert';
import 'dart:typed_data';

/// Decodes a message payload as text without throwing.
///
/// `Message.string` in `dart_nats` does a strict `utf8.decode`, which throws
/// a `FormatException` on any payload that isn't valid UTF-8 (binary data, a
/// truncated multi-byte sequence, etc). On a varied enough message set that
/// happens often enough to matter, and since this call sits in `build()` in
/// several places, an uncaught throw there red-boxes that list row. Decoding
/// with `allowMalformed` instead swaps invalid sequences for U+FFFD rather
/// than throwing, so a garbled payload just displays as garbled text.
String decodeMessageText(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// Compact rendering of a count for tight UI spots like the Pause button's
/// buffered-message badge: `999` -> `"999"`, `1000` -> `"1k"`,
/// `1100` -> `"1.1k"`, `12345` -> `"12k"` — short enough to stay readable
/// regardless of how large a paused backlog grows.
String formatCompactCount(int n) {
  if (n < 1000) return '$n';
  final thousands = n / 1000;
  final rounded = thousands < 10
      ? (thousands * 10).round() / 10
      : thousands.round().toDouble();
  final text = rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
  return '${text}k';
}
