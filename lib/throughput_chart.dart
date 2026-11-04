import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format_utils.dart';
import 'jetstream_manager.dart' show formatBytes;
import 'server_monitor.dart';

/// Series colors for the throughput chart, picked to stay apart for the
/// common kinds of color blindness on both themes' surfaces.
Color throughputInColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFF4A90DA) : const Color(0xFF2F6FB5);
Color throughputOutColor(Brightness b) =>
    b == Brightness.dark ? const Color(0xFFC97A3C) : const Color(0xFFB8662A);

/// `1,234/s` or `1.2 MB/s`.
String formatThroughputRate(double perSecond, {required bool bytes}) => bytes
    ? '${formatBytes(perSecond.round())}/s'
    : '${formatGroupedCount(perSecond.round())}/s';

/// Messages (or bytes) per second in and out over the last two minutes,
/// from a [ThroughputHistory]. Hovering shows the values at that point.
class ThroughputChart extends StatefulWidget {
  const ThroughputChart({
    super.key,
    required this.samples,
    required this.version,
    required this.bytes,
    this.height = 180,
  });

  final List<ThroughputSample> samples;

  /// [ThroughputHistory.version]: the chart repaints only when it changes.
  final int version;
  final bool bytes;
  final double height;

  @override
  State<ThroughputChart> createState() => _ThroughputChartState();
}

class _ThroughputChartState extends State<ThroughputChart> {
  int? _hover;

  @override
  void didUpdateWidget(covariant ThroughputChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hover != null && _hover! >= widget.samples.length) _hover = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = widget.samples;
    if (samples.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Collecting data. The chart fills in as polls arrive.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    final colors = _ChartColors(
      inColor: throughputInColor(theme.brightness),
      outColor: throughputOutColor(theme.brightness),
      grid: theme.colorScheme.outlineVariant,
      crosshair: theme.colorScheme.outline,
      surface: theme.colorScheme.surface,
      label: theme.textTheme.labelSmall!
          .copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final geometry = _ChartGeometry(
            samples, Size(constraints.maxWidth, widget.height), widget.bytes);
        final hover = _hover;
        return MouseRegion(
          onHover: (e) => setState(
              () => _hover = geometry.nearestIndex(e.localPosition.dx)),
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _ThroughputPainter(
                    geometry: geometry,
                    colors: colors,
                    version: widget.version,
                    hover: hover,
                  ),
                ),
              ),
              if (hover != null)
                _tooltip(context, geometry, samples[hover],
                    geometry.x(samples[hover].time), constraints.maxWidth),
            ],
          ),
        );
      }),
    );
  }

  Widget _tooltip(BuildContext context, _ChartGeometry geometry,
      ThroughputSample sample, double x, double width) {
    final theme = Theme.of(context);
    final ago = geometry.latest.difference(sample.time).inSeconds;
    const tooltipWidth = 150.0;
    final left =
        (x + 12 + tooltipWidth > width) ? x - 12 - tooltipWidth : x + 12;
    Widget row(Color color, String label, double value) => Row(
          children: [
            Container(width: 10, height: 3, color: color),
            const SizedBox(width: 6),
            Text('$label ${formatThroughputRate(value, bytes: widget.bytes)}',
                style: theme.textTheme.bodySmall),
          ],
        );
    return Positioned(
      left: math.max(0, left),
      top: 8,
      width: tooltipWidth,
      child: IgnorePointer(
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ago <= 0 ? 'now' : '${ago}s ago',
                    style: theme.textTheme.labelMedium),
                row(throughputInColor(theme.brightness), 'In',
                    widget.bytes ? sample.inBytes : sample.inMsgs),
                row(throughputOutColor(theme.brightness), 'Out',
                    widget.bytes ? sample.outBytes : sample.outMsgs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartColors {
  const _ChartColors({
    required this.inColor,
    required this.outColor,
    required this.grid,
    required this.crosshair,
    required this.surface,
    required this.label,
  });
  final Color inColor;
  final Color outColor;
  final Color grid;
  final Color crosshair;
  final Color surface;
  final TextStyle label;
}

/// Where everything goes: one scale shared by the painter, the hover hit
/// test and the tooltip.
class _ChartGeometry {
  _ChartGeometry(this.samples, this.size, this.bytes)
      : latest = samples.last.time {
    var peak = 0.0;
    for (final s in samples) {
      peak = math.max(peak, math.max(inOf(s), outOf(s)));
    }
    max = _niceCeiling(peak * 1.05);
  }

  static const double left = 56;
  static const double right = 12;
  static const double top = 10;
  static const double bottom = 22;

  final List<ThroughputSample> samples;
  final Size size;
  final bool bytes;
  final DateTime latest;
  late final double max;

  double inOf(ThroughputSample s) => bytes ? s.inBytes : s.inMsgs;
  double outOf(ThroughputSample s) => bytes ? s.outBytes : s.outMsgs;

  double get plotWidth => size.width - left - right;
  double get plotBottom => size.height - bottom;

  /// Two minutes ago at the left edge, the newest sample at the right.
  double x(DateTime t) {
    final ago = latest.difference(t).inMilliseconds /
        ThroughputHistory.window.inMilliseconds;
    return left + plotWidth * (1 - ago);
  }

  double y(double v) =>
      top + (plotBottom - top) * (1 - (max == 0 ? 0 : v / max));

  int nearestIndex(double dx) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < samples.length; i++) {
      final d = (x(samples[i].time) - dx).abs();
      if (d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  String axisLabel(double v) {
    if (bytes) return formatBytes(v.round());
    if (v >= 1e6) return '${_trim(v / 1e6)}M';
    if (v >= 1e3) return '${_trim(v / 1e3)}k';
    return _trim(v);
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// The smallest 1/2/2.5/5 × 10ⁿ at or above [v], so the four gridlines
  /// land on round numbers.
  static double _niceCeiling(double v) {
    if (v <= 0) return 1;
    final magnitude =
        math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final step in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (step * magnitude >= v) return step * magnitude;
    }
    return 10 * magnitude;
  }
}

class _ThroughputPainter extends CustomPainter {
  _ThroughputPainter({
    required this.geometry,
    required this.colors,
    required this.version,
    required this.hover,
  });

  final _ChartGeometry geometry;
  final _ChartColors colors;
  final int version;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final gridPaint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final v = g.max * k / 4;
      final y = g.y(v);
      canvas.drawLine(Offset(_ChartGeometry.left, y),
          Offset(size.width - _ChartGeometry.right, y), gridPaint);
      _text(canvas, g.axisLabel(v), Offset(_ChartGeometry.left - 8, y),
          alignRight: true);
    }
    final labelY = size.height - _ChartGeometry.bottom / 2;
    _text(canvas, '2m ago', Offset(_ChartGeometry.left, labelY));
    _text(
        canvas, '1m ago', Offset(_ChartGeometry.left + g.plotWidth / 2, labelY),
        center: true);
    _text(canvas, 'now', Offset(size.width - _ChartGeometry.right, labelY),
        alignRight: true);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(_ChartGeometry.left, 0,
        size.width - _ChartGeometry.right, size.height));
    _series(canvas, g.outOf, colors.outColor);
    _series(canvas, g.inOf, colors.inColor);
    canvas.restore();

    final index = hover ?? g.samples.length - 1;
    final sample = g.samples[index];
    final x = g.x(sample.time);
    if (hover != null) {
      canvas.drawLine(
          Offset(x, _ChartGeometry.top),
          Offset(x, g.plotBottom),
          Paint()
            ..color = colors.crosshair
            ..strokeWidth = 1);
    }
    for (final (value, color) in [
      (g.outOf(sample), colors.outColor),
      (g.inOf(sample), colors.inColor),
    ]) {
      final center = Offset(x, g.y(value));
      canvas.drawCircle(center, 6, Paint()..color = colors.surface);
      canvas.drawCircle(center, 4, Paint()..color = color);
    }
  }

  /// One line plus a faint area under it, broken wherever polls were missed.
  void _series(
      Canvas canvas, double Function(ThroughputSample) value, Color color) {
    final g = geometry;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color.withValues(alpha: 0.10);

    var start = 0;
    for (var i = 1; i <= g.samples.length; i++) {
      if (i < g.samples.length && !g.samples[i].gapBefore) continue;
      final run = g.samples.sublist(start, i);
      start = i;
      if (run.length < 2) continue;
      final path = Path();
      for (var j = 0; j < run.length; j++) {
        final p = Offset(g.x(run[j].time), g.y(value(run[j])));
        j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      final area = Path.from(path)
        ..lineTo(g.x(run.last.time), g.plotBottom)
        ..lineTo(g.x(run.first.time), g.plotBottom)
        ..close();
      canvas.drawPath(area, fill);
      canvas.drawPath(path, line);
    }
  }

  void _text(Canvas canvas, String text, Offset anchor,
      {bool alignRight = false, bool center = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: colors.label),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight
        ? anchor.dx - painter.width
        : center
            ? anchor.dx - painter.width / 2
            : anchor.dx;
    painter.paint(canvas, Offset(dx, anchor.dy - painter.height / 2));
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _ThroughputPainter old) =>
      old.version != version ||
      old.hover != hover ||
      old.geometry.bytes != geometry.bytes ||
      old.geometry.size != geometry.size ||
      old.colors.inColor != colors.inColor ||
      old.colors.grid != colors.grid;
}
