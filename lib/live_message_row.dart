import 'package:flutter/material.dart';

import 'message_font.dart';
import 'message_row_metrics.dart';
import 'message_wrap.dart';
import 'pinned_fields.dart';
import 'regex_text_highlight.dart';

/// The pinned values to show in a row, with the column widths they line up
/// in. Null on a row that has none of the pinned fields.
class RowPins {
  final List<PinnedPath> paths;
  final List<PinnedValue?> values;
  final List<double> columnWidths;

  const RowPins(this.paths, this.values, this.columnWidths);
}

/// One Live Messages row: the subscription color bar, pinned fields, the
/// payload and the trailing timestamp, subject chip and ⋮ menu.
///
/// Single-line rows ([wrap] null) keep the long-standing layout. Multi-line
/// rows draw the payload as [wrap]'s pre-computed lines and give the
/// trailing area a fixed [trailingWidth], which is what lets the list know
/// the row's height without laying it out (see `message_row_metrics.dart`).
class LiveMessageRow extends StatelessWidget {
  final String text;
  final String subject;
  final String findTerm;
  final double fontSize;
  final double extent;
  final Color tileColor;
  final Color? barColor;
  final bool showColorBar;
  final String? timestamp;
  final bool showSubject;

  /// Browse Messages' stream sequence (`#42`), shown in a chip before the
  /// subject. Null in Live Messages.
  final String? sequenceLabel;
  final double subjectMaxWidth;
  final WrapResult? wrap;
  final double? trailingWidth;
  final RowPins? pins;
  final VoidCallback onTap;
  final Widget menuButton;
  final void Function(int pinIndex, Offset globalPosition) onPinTap;

  const LiveMessageRow({
    super.key,
    required this.text,
    required this.subject,
    required this.findTerm,
    required this.fontSize,
    required this.extent,
    required this.tileColor,
    required this.barColor,
    required this.showColorBar,
    required this.timestamp,
    required this.showSubject,
    this.sequenceLabel,
    this.subjectMaxWidth = MessageRowGeometry.chipMaxWidth,
    required this.wrap,
    required this.trailingWidth,
    required this.pins,
    required this.onTap,
    required this.menuButton,
    required this.onPinTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final multiLine = wrap != null;
    final trailing = Row(
      mainAxisSize: multiLine ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (timestamp != null)
          Padding(
            padding: const EdgeInsets.only(
                right: MessageRowGeometry.timestampEndPadding),
            child: Text(
              timestamp!,
              style: timestampTextStyle(
                Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        if (sequenceLabel != null)
          Padding(
            padding:
                const EdgeInsets.only(right: MessageRowGeometry.chipEndPadding),
            child: Chip(label: Text(sequenceLabel!)),
          ),
        if (showSubject)
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: subjectMaxWidth),
              child: Tooltip(
                message: subject,
                child: Padding(
                  padding: const EdgeInsets.only(
                      right: MessageRowGeometry.chipEndPadding),
                  child: Chip(
                      label: Text(subject,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: colorScheme.onSurface,
                          ))),
                ),
              ),
            ),
          ),
        menuButton,
      ],
    );

    final tile = ListTile(
      // ListTile centers its title within its own *computed natural* height,
      // not whatever height it's actually given -- when the 56px floor in
      // messageRowExtent kicks in (small font sizes), that natural height is
      // smaller than the row's real extent, and without this the leftover
      // space silently lands entirely below the text instead of being split
      // evenly. Telling it the *real* target height makes its own centering
      // math correct.
      minTileHeight: extent,
      // Explicit (and equal to the Material 3 defaults) so the title width
      // in message_row_metrics.dart is exact.
      contentPadding: const EdgeInsetsDirectional.only(
          start: MessageRowGeometry.tileStartPadding,
          end: MessageRowGeometry.tileEndPadding),
      horizontalTitleGap: MessageRowGeometry.titleGap,
      // Multi-line rows keep the trailing controls in the first 56px, where
      // a single-line row has them, instead of centered on a tall row.
      titleAlignment: multiLine
          ? ListTileTitleAlignment.top
          : ListTileTitleAlignment.center,
      minVerticalPadding:
          multiLine ? MessageRowGeometry.trailingTopPadding : null,
      title: RegexTextHighlight(
        text: text,
        searchTerm: findTerm,
        fontSize: fontSize,
        style: messagePayloadStyle(fontSize),
        strutStyle: messagePayloadStrut(fontSize),
        highlightStyle: TextStyle(
          background: Paint()..color = colorScheme.inversePrimary,
          fontSize: fontSize,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        wrap: wrap,
      ),
      tileColor: tileColor,
      onTap: onTap,
      trailing: multiLine
          ? SizedBox(
              width: trailingWidth,
              height: MessageRowGeometry.trailingHeight,
              child: trailing,
            )
          : trailing,
    );

    return Material(
      // A full-height bar (rather than a small leading dot) reads more
      // clearly at a glance and doesn't compete with ListTile's own
      // leading/minLeadingWidth slot. CrossAxisAlignment.stretch makes the
      // bar span the row's full extent.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showColorBar)
            Container(
              key: const ValueKey('subscriptionColorBar'),
              width: MessageRowGeometry.colorBarWidth,
              color: barColor ?? Colors.transparent,
            ),
          if (pins != null)
            ColoredBox(
              color: tileColor,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTap,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: MessageRowGeometry.minRowExtent,
                    child: Padding(
                      padding: const EdgeInsets.only(left: pinAreaStartPadding),
                      child: PinnedFieldCells(pins: pins!, onTap: onPinTap),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: tile),
        ],
      ),
    );
  }
}

/// A row's pinned values: one cell per pinned path, each with the field
/// name in small caption text above its value.
class PinnedFieldCells extends StatelessWidget {
  final RowPins pins;
  final void Function(int pinIndex, Offset globalPosition) onTap;

  const PinnedFieldCells({super.key, required this.pins, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final captionStyle = pinCaptionStyle(theme);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < pins.paths.length; k++) ...[
          if (k > 0) const SizedBox(width: pinCellGap),
          _cell(context, k, captionStyle, colorScheme),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, int k, TextStyle captionStyle,
      ColorScheme colorScheme) {
    final path = pins.paths[k];
    final value = pins.values[k];
    final valueStyle = pinValueStyle(
        color: value == null
            ? colorScheme.onSurface.withValues(alpha: 0.35)
            : colorScheme.onSurface);
    return Tooltip(
      message: value == null
          ? '${path.path}: not in this message'
          : '${path.path}: ${value.full}',
      child: Material(
        key: ValueKey('pinnedCell_$k'),
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTapUp: (details) => onTap(k, details.globalPosition),
          child: SizedBox(
            width: pins.columnWidths[k],
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(path.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: captionStyle),
                  Text(value?.display ?? '—',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Caption style for a pinned field's name. Also what its width is measured
/// in, so the measured and drawn widths match.
TextStyle pinCaptionStyle(ThemeData theme) =>
    (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontSize: pinCaptionFontSize,
      height: 1.25,
      letterSpacing: 0.2,
      color: theme.colorScheme.onSurfaceVariant,
    );

/// Menu shown when a pinned value is clicked. Values: `copy`, `pin`
/// (open the Pin Fields picker), `unpin`.
List<PopupMenuEntry<String>> pinCellMenuItems(PinnedPath path,
        {required bool hasValue}) =>
    [
      PopupMenuItem(
        value: 'copy',
        enabled: hasValue,
        child: Text('Copy ${path.label} Value'),
      ),
      const PopupMenuItem(value: 'pin', child: Text('Pin Fields…')),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'unpin', child: Text('Unpin ${path.label}')),
    ];
