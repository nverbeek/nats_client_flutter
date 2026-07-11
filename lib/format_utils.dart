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
