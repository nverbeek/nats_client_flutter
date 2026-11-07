import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'exact_extent_list.dart';
import 'format_utils.dart';
import 'live_message_row.dart';
import 'message_font.dart';
import 'message_row_metrics.dart';
import 'message_wrap.dart';
import 'pinned_fields.dart';
import 'scroll_anchor.dart';

/// The message-list display settings a list needs from the app: how many
/// lines a row may wrap to, whether rows show the subject chip, and the
/// pinned fields (with a way to change them from a row's "Pin Fields…").
class MessageListDisplay {
  final int maxLines;
  final bool showSubject;
  final List<String> pinnedFields;
  final ValueChanged<List<String>>? onPinnedFieldsChanged;

  const MessageListDisplay({
    this.maxLines = 1,
    this.showSubject = true,
    this.pinnedFields = const [],
    this.onPinnedFieldsChanged,
  });
}

/// Row-height bookkeeping for a message list (Live Messages, Browse
/// Messages): every row's height is known up front, so prepend compensation,
/// the scrollbar and "at the top" stay exact even with multi-line rows.
///
/// Holds the pinned-field state, the wrap cache, the list width and the
/// measured styles; the owning State feeds it settings (from `build`), calls
/// [noteWidth] from a `LayoutBuilder` around its list, and builds the list
/// with [buildList].
///
/// Each row's height is cached per message. Every setting that can change a
/// height bumps a generation counter, which invalidates the cache, so the
/// list can sum all heights on every layout (for an exact scroll extent)
/// without re-measuring anything.
class MessageListLayout {
  MessageListLayout({
    required this.subjectChipMaxWidth,
    bool showColorBar = false,
    this.hasCapturedAt = _never,
    this.sequenceLabel = _noLabel,
  }) : _showColorBar = showColorBar;

  static bool _never(Message<dynamic> _) => false;
  static String? _noLabel(Message<dynamic> _) => null;

  final PinnedFields pins = PinnedFields();
  final WrapCache _wrapCache = WrapCache();
  final Expando<_CachedExtent> _extents = Expando<_CachedExtent>('extent');

  /// Bumped by every setting that can change a row's height.
  int _generation = 0;

  final double subjectChipMaxWidth;

  /// Whether a message has an arrival time to show (Live Messages). Per
  /// message and fixed; whether timestamps show at all is
  /// [timestampsVisible].
  bool Function(Message<dynamic> message) hasCapturedAt;

  /// Browse Messages' `#sequence` chip label. Fixed per message.
  String? Function(Message<dynamic> message) sequenceLabel;

  bool _showColorBar;
  bool get showColorBar => _showColorBar;
  set showColorBar(bool value) => _set(_showColorBar != value, () {
        _showColorBar = value;
      });

  bool _timestampsVisible = false;
  bool get timestampsVisible => _timestampsVisible;
  set timestampsVisible(bool value) => _set(_timestampsVisible != value, () {
        _timestampsVisible = value;
      });

  int _maxLines = 1;
  int get maxLines => _maxLines;
  set maxLines(int value) => _set(_maxLines != value, () {
        _maxLines = value;
      });

  double _fontSize = 14;
  double get fontSize => _fontSize;
  set fontSize(double value) => _set(_fontSize != value, () {
        _fontSize = value;
      });

  bool _showSubject = true;
  bool get showSubject => _showSubject;
  set showSubject(bool value) => _set(_showSubject != value, () {
        _showSubject = value;
      });

  /// Height of every row while [multiLine] is off.
  double _singleLineExtent = MessageRowGeometry.minRowExtent;
  double get singleLineExtent => _singleLineExtent;
  set singleLineExtent(double value) => _set(_singleLineExtent != value, () {
        _singleLineExtent = value;
      });

  /// The list's width as of its last layout.
  double _rowWidth = 0;
  double get rowWidth => _rowWidth;

  TextStyle _chipLabelStyle = const TextStyle();
  TextStyle _timestampStyle = const TextStyle();
  TextStyle _captionStyle =
      const TextStyle(fontSize: pinCaptionFontSize, height: 1.25);

  void _set(bool changed, VoidCallback apply) {
    if (!changed) return;
    apply();
    _generation++;
  }

  bool get multiLine => _maxLines > 1;

  /// Picks up the theme's text styles, which the measurements must match.
  /// Call from the owning State's `build`, after setting [fontSize].
  void updateStyles(ThemeData theme) {
    final chip = (theme.textTheme.labelLarge ?? const TextStyle())
        .copyWith(fontSize: _fontSize);
    final timestamp =
        timestampTextStyle(theme.textTheme.bodyMedium ?? const TextStyle());
    final caption = pinCaptionStyle(theme);
    _set(
        chip != _chipLabelStyle ||
            timestamp != _timestampStyle ||
            caption != _captionStyle, () {
      _chipLabelStyle = chip;
      _timestampStyle = timestamp;
      _captionStyle = caption;
    });
  }

  /// Replaces the pinned fields (invalid sources are skipped) and re-measures
  /// the columns over [messages].
  void setPinnedSources(
      List<String> sources, Iterable<Message<dynamic>> messages) {
    pins.setPaths(
      [
        for (final source in sources)
          if (parsePinnedPath(source) case final path?) path,
      ],
      messages,
      (label) => measureTextWidth(label, _captionStyle),
    );
  }

  /// [message]'s multi-line layout at the current [rowWidth].
  MessageRowLayout layoutFor(Message<dynamic> message) {
    return layoutMessageRow(
      wrapKey: message,
      wrapCache: _wrapCache,
      text: decodeMessageTextFor(message),
      subject: message.subject ?? '',
      hasTimestamp: _timestampsVisible && hasCapturedAt(message),
      sequenceLabel: sequenceLabel(message),
      rowWidth: _rowWidth,
      fontSize: _fontSize,
      maxLines: _maxLines,
      showColorBar: _showColorBar,
      showSubject: _showSubject,
      subjectChipMaxWidth: subjectChipMaxWidth,
      pinAreaWidth: pins.areaWidth(message),
      timestampStyle: _timestampStyle,
      chipLabelStyle: _chipLabelStyle,
    );
  }

  /// [message]'s row height, cached until a setting, the list width or a
  /// pinned column changes.
  double extentFor(Message<dynamic> message) {
    if (!multiLine) return _singleLineExtent;
    final cached = _extents[message];
    final pinsVersion = pins.layoutVersion;
    if (cached != null &&
        cached.generation == _generation &&
        cached.pinsVersion == pinsVersion) {
      return cached.extent;
    }
    final extent = layoutFor(message).extent;
    _extents[message] = _CachedExtent(_generation, pinsVersion, extent);
    return extent;
  }

  /// Total height of [messages], for prepend compensation.
  double heightOf(Iterable<Message<dynamic>> messages) {
    var total = 0.0;
    for (final m in messages) {
      total += extentFor(m);
    }
    return total;
  }

  /// The message list itself: a plain fixed-extent `ListView` while
  /// [multiLine] is off, else an [ExactExtentListView] whose scroll extent
  /// and row positions come from [extentFor].
  ListView buildList({
    required ScrollController controller,
    required List<Message<dynamic>> items,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    if (!multiLine) {
      return ListView.builder(
        controller: controller,
        itemExtent: _singleLineExtent,
        itemCount: items.length,
        itemBuilder: itemBuilder,
      );
    }
    return ExactExtentListView.builder(
      controller: controller,
      itemCount: items.length,
      itemBuilder: itemBuilder,
      extentAt: (index) => extentFor(items[index]),
      // A new token whenever any height may have changed: the list identity
      // and ends (prepend, trim, filter, clear) and the height generation.
      extentsToken: (
        items,
        items.length,
        items.isEmpty ? null : items.first,
        items.isEmpty ? null : items.last,
        _generation,
        pins.layoutVersion,
      ),
    );
  }

  /// [message]'s pinned values for its row, or null when it has none of the
  /// pinned fields or the row is too narrow to show them.
  RowPins? rowPinsFor(Message<dynamic> message) {
    if (fitPinArea(_rowWidth, pins.areaWidth(message)) <= 0) return null;
    final values = pins.valuesFor(message);
    if (values == null) return null;
    return RowPins(pins.paths, values, [
      for (var k = 0; k < values.length; k++) pins.columnWidth(k),
    ]);
  }

  /// The message at scroll [offset] in [items] and how far into it.
  (Message<dynamic>?, double) anchorAt(
          List<Message<dynamic>> items, double offset) =>
      scrollAnchorAt(items, offset, extentFor);

  // --- Deferred scroll jumps -------------------------------------------
  //
  // Keeping the view still when rows above it change means jumping the
  // scroll offset after the frame that laid the new rows out. If the user
  // presses Jump to top in between, that pending jump must not drag them
  // back down: [userJumped] cancels every jump scheduled before it.

  int _jumpEpoch = 0;

  /// Call when the user explicitly moves the list (Jump to top), so jumps
  /// scheduled before it are dropped.
  void userJumped() => _jumpEpoch++;

  /// After this frame, jumps [controller] to [target] (clamped to the list's
  /// range), unless the user jumped in the meantime or [target] gives null.
  void deferJump(ScrollController controller, double? Function() target) {
    final epoch = _jumpEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (epoch != _jumpEpoch || !controller.hasClients) return;
      final to = target();
      if (to == null) return;
      final max = controller.position.maxScrollExtent;
      controller.jumpTo(to > max ? max : (to < 0 ? 0 : to));
    });
  }

  /// After this frame, scrolls [controller] so [anchor] is back where
  /// [anchorAt] found it.
  void _deferRestore(
      ScrollController controller,
      List<Message<dynamic>> Function() items,
      Message<dynamic>? anchor,
      double intra) {
    if (anchor == null) return;
    deferJump(
        controller, () => offsetForAnchor(items(), anchor, intra, extentFor));
  }

  /// Records the list width from its `LayoutBuilder`. When a resize changes
  /// multi-line row heights while scrolled away from the top, the first
  /// visible message is found under the old width and restored after the
  /// frame.
  void noteWidth(
      double width, List<Message<dynamic>> items, ScrollController controller) {
    if (width == _rowWidth) return;
    if (multiLine &&
        _rowWidth > 0 &&
        controller.hasClients &&
        controller.offset > 1.0) {
      final (anchor, intra) = anchorAt(items, controller.offset);
      _deferRestore(controller, () => items, anchor, intra);
    }
    _rowWidth = width;
    pins.widthCap = pinCellWidthCap(width);
    _generation++;
  }

  /// Runs [mutate] through [setState], keeping the first visible message in
  /// place when the change alters row heights (settings, pin columns).
  void keepAnchor(
    ScrollController controller,
    List<Message<dynamic>> Function() items,
    void Function(VoidCallback) setState,
    VoidCallback mutate,
  ) {
    final offset = controller.hasClients ? controller.offset : 0.0;
    if (offset <= 1.0 || items().isEmpty) {
      setState(mutate);
      return;
    }
    final (anchor, intra) = anchorAt(items(), offset);
    setState(mutate);
    _deferRestore(controller, items, anchor, intra);
  }
}

class _CachedExtent {
  final int generation;
  final int pinsVersion;
  final double extent;

  _CachedExtent(this.generation, this.pinsVersion, this.extent);
}

/// Shows the "Pin Fields…"/copy/unpin menu for a click on a pinned value at
/// [globalPosition]. Returns the chosen action (see [pinCellMenuItems]).
Future<String?> showPinCellMenu(BuildContext context, PinnedPath path,
    {required bool hasValue, required Offset globalPosition}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    items: pinCellMenuItems(path, hasValue: hasValue),
  );
}
