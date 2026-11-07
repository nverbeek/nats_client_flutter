import 'package:flutter/painting.dart';

/// The monospace font message payloads render in: Roboto Mono, bundled as a
/// variable font (`assets/fonts/RobotoMono-Variable.ttf`, SIL OFL 1.1) so it
/// works offline and on web without a font fetch.
const String messageMonoFontFamily = 'RobotoMono';

/// Weight of payload text. Every weight of Roboto Mono has the same advance
/// width, so tuning this never changes wrapping or row heights.
const double payloadFontWeight = 400;

/// Weight of pinned-field values, one step heavier than the payload so they
/// stand out a little.
const double pinValueFontWeight = 500;

/// Line height as a multiple of the font size. Fixed (and forced through a
/// strut) so a row's height is exactly `lines * fontSize * this`.
const double messageLineHeightFactor = 1.3;

/// Font size of pinned-field values and of their captions.
const double pinValueFontSize = 12.5;
const double pinCaptionFontSize = 10.5;

/// The payload text style at [fontSize].
TextStyle messagePayloadStyle(double fontSize, {Color? color}) => TextStyle(
      fontFamily: messageMonoFontFamily,
      fontSize: fontSize,
      height: messageLineHeightFactor,
      // Explicit, so a theme's spacing (ListTile titles get 0.5) can't widen
      // every character past the measured advance width.
      letterSpacing: 0,
      wordSpacing: 0,
      fontVariations: const [FontVariation('wght', payloadFontWeight)],
      color: color,
    );

/// A strut that pins every line of payload text to exactly
/// `fontSize * messageLineHeightFactor`, even when a line contains a glyph
/// from a fallback font (an emoji, CJK) that is taller than Roboto Mono.
StrutStyle messagePayloadStrut(double fontSize) => StrutStyle(
      fontFamily: messageMonoFontFamily,
      fontSize: fontSize,
      height: messageLineHeightFactor,
      forceStrutHeight: true,
    );

/// The pinned-value text style.
TextStyle pinValueStyle({Color? color}) => TextStyle(
      fontFamily: messageMonoFontFamily,
      fontSize: pinValueFontSize,
      letterSpacing: 0,
      wordSpacing: 0,
      fontVariations: const [FontVariation('wght', pinValueFontWeight)],
      color: color,
    );

final Map<double, double> _charWidthCache = {};

/// Advance width of one Roboto Mono character at [fontSize], measured once
/// per size with a [TextPainter] and cached.
double monoCharWidth(double fontSize) {
  return _charWidthCache[fontSize] ??= () {
    const sample = 100;
    final painter = TextPainter(
      text: TextSpan(text: '0' * sample, style: messagePayloadStyle(fontSize)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width / sample;
    painter.dispose();
    return width;
  }();
}

final Map<double, (double, double)> _lineMetricsCache = {};

/// Height of [lines] lines of payload text at [fontSize], as text layout
/// actually draws it. Line heights get rounded during layout (14px * 1.3
/// draws as 18, not 18.2), so this measures a one- and a two-line block once
/// per size rather than trusting the multiplication.
double monoTextBlockHeight(double fontSize, int lines) {
  final (first, perLine) = _lineMetricsCache[fontSize] ??= () {
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: messagePayloadStyle(fontSize)),
        strutStyle: messagePayloadStrut(fontSize),
        textDirection: TextDirection.ltr,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final one = measure('0');
    final two = measure('0\n0');
    return (one, two - one);
  }();
  return first + (lines - 1) * perLine;
}

final Map<(String, TextStyle), double> _textWidthCache = {};

/// Width of [text] laid out on one line in [style], cached by both. Used for
/// a small, bounded set of strings (subjects, field names, the timestamp
/// template), never per message payload.
double measureTextWidth(String text, TextStyle style) {
  if (_textWidthCache.length > 4000) _textWidthCache.clear();
  return _textWidthCache[(text, style)] ??= () {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }();
}
