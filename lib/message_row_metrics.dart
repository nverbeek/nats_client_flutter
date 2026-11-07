import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'message_font.dart';
import 'message_wrap.dart';

/// Geometry of a Live Messages row, written down as constants so a row's
/// text width (and from it, its wrapped line count and height) can be worked
/// out without laying the row out.
///
/// The row is `[color bar][pin area][ListTile(title, trailing)]`, and the
/// ListTile's own padding and title gap are set explicitly to these values.
/// ListTile gives its title exactly
/// `tileWidth - start - end - max(trailingWidth + gap, 32)`.
///
/// The end side is tighter than ListTile's defaults (24 end, 16 gap) to give
/// message text more room: the ⋮ button carries 8px of its own padding
/// around its icon, so 8 + 8 puts the icon 16px from the row's edge (the
/// Material 3 list spec's end padding) and leaves about 16px between the
/// text and the icon.
class MessageRowGeometry {
  MessageRowGeometry._();

  static const double colorBarWidth = 4;
  static const double tileStartPadding = 16;
  static const double tileEndPadding = 8;
  static const double titleGap = 8;

  /// ListTile never reserves less than this for its trailing widget + gap.
  static const double minTrailingReserve = 32;

  /// The row's ⋮ button, drawn in a box of exactly this size (Material 3's
  /// standard icon-button size), so the reserved width is the drawn width.
  static const double menuButtonWidth = 40;

  /// Height of the trailing area in a multi-line row, which sits in the first
  /// 56px of the row (see [trailingTopPadding]).
  static const double trailingHeight = 48;
  static const double trailingTopPadding = (minRowExtent - trailingHeight) / 2;

  static const double timestampEndPadding = 6;
  static const double timestampFontSize = 11;

  /// Subject chip: Material 3 `Chip` padding (8 + 8) + label padding (at most
  /// 8 + 8) + border (1 + 1), plus 1px of rounding slack.
  static const double chipChrome = 35;
  static const double chipEndPadding = 5;
  static const double chipMaxWidth = 450;

  static const double minRowExtent = 56;

  /// The payload never gets narrower than this; the trailing area gives way.
  static const double minTitleWidth = 160;

  /// Pinned fields only show when this much row width is left beside them.
  static const double minWidthBesidePins = 480;
  static const double rowVerticalPadding = 24;
}

/// Height of a message row showing [lines] lines at [fontSize]. With one
/// line this is the single-line extent the list has always used.
double messageRowExtent(int lines, double fontSize) {
  final height = monoTextBlockHeight(fontSize, lines) +
      MessageRowGeometry.rowVerticalPadding;
  return math.max(height, MessageRowGeometry.minRowExtent);
}

/// [pinAreaWidth] if the row is wide enough to show the pinned fields and
/// still leave [MessageRowGeometry.minWidthBesidePins] for the rest, else 0
/// (the row then shows no pins, rather than overflowing).
double fitPinArea(double rowWidth, double pinAreaWidth) =>
    rowWidth - pinAreaWidth >= MessageRowGeometry.minWidthBesidePins
        ? pinAreaWidth
        : 0;

/// [trailingWidth], shrunk if needed so the title keeps at least
/// [MessageRowGeometry.minTitleWidth] (the subject chip then ellipsizes).
double fitTrailingWidth({
  required double rowWidth,
  required bool showColorBar,
  required double pinAreaWidth,
  required double trailingWidth,
}) {
  final available = rowWidth -
      (showColorBar ? MessageRowGeometry.colorBarWidth : 0) -
      pinAreaWidth -
      MessageRowGeometry.tileStartPadding -
      MessageRowGeometry.tileEndPadding -
      MessageRowGeometry.titleGap -
      MessageRowGeometry.minTitleWidth;
  return math.max(
      math.min(trailingWidth, available), MessageRowGeometry.menuButtonWidth);
}

/// The row timestamp's text style: [base] (the theme's body style) with
/// every property that affects width set explicitly, so the drawn text
/// can't pick up ListTile's trailing letter spacing and outgrow the width
/// [timestampSlotWidth] measured with this same style.
TextStyle timestampTextStyle(TextStyle base, {Color? color}) => base.copyWith(
      fontSize: MessageRowGeometry.timestampFontSize,
      letterSpacing: 0,
      wordSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color,
    );

/// Width the trailing area reserves for a timestamp in [style].
double timestampSlotWidth(TextStyle style) {
  final am = measureTextWidth('00:00:00.000 AM', style);
  final pm = measureTextWidth('00:00:00.000 PM', style);
  return (math.max(am, pm) + MessageRowGeometry.timestampEndPadding + 1)
      .ceilToDouble();
}

/// Width the trailing area reserves for [subject]'s chip, whose label
/// renders in [labelStyle], at most [maxWidth].
double subjectChipSlotWidth(String subject, TextStyle labelStyle,
    {double maxWidth = MessageRowGeometry.chipMaxWidth}) {
  final label = measureTextWidth(subject, labelStyle);
  return math.min(
      maxWidth,
      (label +
              MessageRowGeometry.chipChrome +
              MessageRowGeometry.chipEndPadding)
          .ceilToDouble());
}

/// Width the trailing area reserves for a stream-sequence chip (Browse
/// Messages) labelled [label]. Never shrinks, unlike the subject chip.
double sequenceChipSlotWidth(String label, TextStyle labelStyle) =>
    (measureTextWidth(label, labelStyle) +
            MessageRowGeometry.chipChrome +
            MessageRowGeometry.chipEndPadding)
        .ceilToDouble();

/// Fixed width of a multi-line row's trailing area.
double trailingSlotWidth({
  required double timestampWidth,
  required double subjectChipWidth,
  double sequenceChipWidth = 0,
}) =>
    timestampWidth +
    sequenceChipWidth +
    subjectChipWidth +
    MessageRowGeometry.menuButtonWidth;

/// Width the ListTile gives a row's title (the payload text).
double messageTitleWidth({
  required double rowWidth,
  required bool showColorBar,
  required double pinAreaWidth,
  required double trailingWidth,
}) {
  final tileWidth = rowWidth -
      (showColorBar ? MessageRowGeometry.colorBarWidth : 0) -
      pinAreaWidth;
  final trailingReserve = math.max(trailingWidth + MessageRowGeometry.titleGap,
      MessageRowGeometry.minTrailingReserve);
  return tileWidth -
      MessageRowGeometry.tileStartPadding -
      MessageRowGeometry.tileEndPadding -
      trailingReserve;
}

/// How many monospace characters fit on one line of [titleWidth] at
/// [fontSize]. At least 1, so a very narrow window still makes progress.
int charsPerLine(double titleWidth, double fontSize) {
  // Half a pixel of slack so float rounding in text layout can never push
  // the last character of a full line past the edge.
  final perLine = ((titleWidth - 0.5) / monoCharWidth(fontSize)).floor();
  return perLine < 1 ? 1 : perLine;
}

/// A multi-line row's wrapped text, height, and the fixed widths its pin
/// area and trailing area get.
class MessageRowLayout {
  final WrapResult wrap;
  final double extent;
  final double pinAreaWidth;
  final double trailingWidth;

  const MessageRowLayout(
      this.wrap, this.extent, this.pinAreaWidth, this.trailingWidth);
}

/// Lays out one multi-line message row at [rowWidth] without building it:
/// pure arithmetic over cached measurements, because the list calls this
/// for every row above the viewport on each layout. [wrapKey] identifies
/// the message for [wrapCache]. [pinAreaWidth] is the row's full pin area
/// (0 if it has none of the pinned fields).
MessageRowLayout layoutMessageRow({
  required Object wrapKey,
  required WrapCache wrapCache,
  required String text,
  required String subject,
  required bool hasTimestamp,
  String? sequenceLabel,
  required double rowWidth,
  required double fontSize,
  required int maxLines,
  required bool showColorBar,
  required bool showSubject,
  double subjectChipMaxWidth = MessageRowGeometry.chipMaxWidth,
  required double pinAreaWidth,
  required TextStyle timestampStyle,
  required TextStyle chipLabelStyle,
}) {
  final pinArea = fitPinArea(rowWidth, pinAreaWidth);
  final trailingWidth = fitTrailingWidth(
    rowWidth: rowWidth,
    showColorBar: showColorBar,
    pinAreaWidth: pinArea,
    trailingWidth: trailingSlotWidth(
      timestampWidth: hasTimestamp ? timestampSlotWidth(timestampStyle) : 0,
      sequenceChipWidth: sequenceLabel == null
          ? 0
          : sequenceChipSlotWidth(sequenceLabel, chipLabelStyle),
      subjectChipWidth: showSubject
          ? subjectChipSlotWidth(subject, chipLabelStyle,
              maxWidth: subjectChipMaxWidth)
          : 0,
    ),
  );
  final titleWidth = messageTitleWidth(
    rowWidth: rowWidth,
    showColorBar: showColorBar,
    pinAreaWidth: pinArea,
    trailingWidth: trailingWidth,
  );
  final wrap = wrapCache.wrapFor(
      wrapKey, text, charsPerLine(titleWidth, fontSize), maxLines);
  return MessageRowLayout(
      wrap, messageRowExtent(wrap.lineCount, fontSize), pinArea, trailingWidth);
}
