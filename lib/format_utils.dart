import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;

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

/// Per-message cache of [decodeMessageText], keyed by object identity so it
/// never keeps a `Message` alive on its own. Live-message lists re-decode the
/// same payload on every filter pass and every row rebuild; for a large
/// backlog that's a repeated UTF-8 decode of the same bytes for no reason.
final Expando<String> _decodedMessageText = Expando<String>();

/// Returns the decoded text for [message], computing and caching it on first
/// access via [decodeMessageText].
String decodeMessageTextFor(Message<dynamic> message) =>
    _decodedMessageText[message] ??= decodeMessageText(message.byte);

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

/// Thousands-comma grouping for exact counts: `4210` -> `"4,210"`. Distinct
/// from [formatCompactCount]'s `"4.2k"` style, which fits Pause's "roughly
/// how much" framing but not Replay's exact-count progress/preview framing.
String formatGroupedCount(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return (n < 0 ? '-' : '') + buffer.toString();
}

/// Human-readable estimate of a [Duration] for Replay's live preview:
/// `~450ms`, `~2m 15s`, `<1s` for a duration that rounds down to nothing.
String formatEstimatedDuration(Duration d) {
  if (d.inMilliseconds <= 0) return '<1s';
  if (d.inMilliseconds < 1000) return '~${d.inMilliseconds}ms';
  final totalSeconds = d.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return minutes == 0 ? '~${seconds}s' : '~${minutes}m ${seconds}s';
}

/// Truncates an error's `toString()` to [maxLength] characters (appending an
/// ellipsis if it was cut), for surfacing an unclassified connection failure
/// in a SnackBar without risking a wall of stack-trace-like text.
String truncatedErrorDetail(Object error, {int maxLength = 120}) {
  final text = error.toString();
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}…';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

/// `dt`'s hour on a 12-hour clock (`0` maps to `12`, matching civilian
/// AM/PM usage) and which half of the day it's in.
(int hour12, String period) _hour12AndPeriod(DateTime local) {
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final period = local.hour < 12 ? 'AM' : 'PM';
  return (hour12, period);
}

/// Renders [dt] as a local-time 12-hour `hh:mm:ss.SSS AM/PM` clock, for the
/// "very thin" per-row timestamp in Live Messages -- deliberately no date
/// component, since a live list is implicitly "today" and the row has no
/// space to spare. Pure string formatting (no `intl` dependency) to match
/// this file's existing `format*` helpers.
String formatTimeOfDay(DateTime dt) {
  final local = dt.toLocal();
  final (hour12, period) = _hour12AndPeriod(local);
  final millis = local.millisecond.toString().padLeft(3, '0');
  return '${_twoDigits(hour12)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}'
      '.$millis $period';
}

/// Renders [dt] as a full local `yyyy-MM-dd hh:mm:ss.SSS AM/PM` timestamp,
/// for the Message Detail dialog's "Received" row where there's room for
/// the whole thing and the date actually matters (e.g. inspecting an old
/// export).
String formatFullTimestamp(DateTime dt) {
  final local = dt.toLocal();
  final (hour12, period) = _hour12AndPeriod(local);
  final millis = local.millisecond.toString().padLeft(3, '0');
  return '${local.year.toString().padLeft(4, '0')}-${_twoDigits(local.month)}-'
      '${_twoDigits(local.day)} ${_twoDigits(hour12)}:${_twoDigits(local.minute)}:'
      '${_twoDigits(local.second)}.$millis $period';
}
