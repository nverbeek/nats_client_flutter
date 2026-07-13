import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'color_tab_chip.dart';
import 'subscription_info.dart';

/// Compact chip-based replacement for the old free-text Subjects field.
/// Renders one [InputChip] per subscription (color swatch avatar + subject +
/// optional queue-group badge), a trailing "+" to add a new subscription,
/// and collapses overflow into a single "+N more" chip once the available
/// width runs out — tapping it opens the full Subscription Manager dialog.
///
/// Overflow is decided from *real* measured widths, not an estimate: an
/// invisible [Offstage] copy of every chip/button is laid out unconstrained
/// (see [_MeasureSize]) and its measured size feeds back via `setState` on
/// the following frame. The very first frame (before any measurement
/// exists) falls back to a rough [TextPainter] estimate so there's no
/// flash of "everything collapsed" -- it self-corrects a frame later, which
/// is imperceptible since chip content changes rarely (only on
/// add/remove/edit, not every frame).
class SubjectChipsRow extends StatefulWidget {
  final List<SubscriptionInfo> subscriptions;
  final bool isDark;
  final bool showSubscriptionColors;
  final ValueChanged<SubscriptionInfo> onTapChip;
  final ValueChanged<SubscriptionInfo> onRemoveChip;
  final VoidCallback onAdd;
  final VoidCallback onOpenManager;

  const SubjectChipsRow({
    super.key,
    required this.subscriptions,
    required this.isDark,
    required this.showSubscriptionColors,
    required this.onTapChip,
    required this.onRemoveChip,
    required this.onAdd,
    required this.onOpenManager,
  });

  @override
  State<SubjectChipsRow> createState() => _SubjectChipsRowState();
}

class _SubjectChipsRowState extends State<SubjectChipsRow> {
  // First-frame-only fallback, before real measurements arrive.
  static const double _addButtonWidth = 44;
  static const double _overflowChipWidth = 96;
  static const double _chipOverhead = 64;
  static const _labelStyle = TextStyle(fontSize: 13);
  static const double _chipGap = 10;

  final Map<SubscriptionInfo, double> _measuredChipWidths = {};
  double? _measuredAddButtonWidth;
  double? _measuredOverflowWidth;

  // Owns focus for the field-like tap target (see build()'s GestureDetector)
  // so tapping empty space in the row -- not a chip or the add button --
  // just focuses the field, like tapping a normal TextFormField does.
  final FocusNode _focusNode = FocusNode(debugLabel: 'SubjectChipsRow');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  String _labelFor(SubscriptionInfo info) {
    final queueGroup = info.queueGroup;
    return (queueGroup != null && queueGroup.isNotEmpty)
        ? '${info.subject} · $queueGroup'
        : info.subject;
  }

  double _estimateChipWidth(SubscriptionInfo info) {
    final painter = TextPainter(
      text: TextSpan(text: _labelFor(info), style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + _chipOverhead;
  }

  // setState during the same frame's layout would assert -- defer to the
  // next frame, and only rebuild when a measurement actually changed (so
  // this converges after 1-2 frames instead of looping forever).
  void _recordChipWidth(SubscriptionInfo info, double width) {
    if (_measuredChipWidths[info] == width) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _measuredChipWidths[info] = width);
    });
  }

  void _recordAddButtonWidth(double width) {
    if (_measuredAddButtonWidth == width) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _measuredAddButtonWidth = width);
    });
  }

  void _recordOverflowWidth(double width) {
    if (_measuredOverflowWidth == width) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _measuredOverflowWidth = width);
    });
  }

  // The visible copy gets an explicit, specific tooltip -- "Remove
  // subscription", matching SubscriptionManagerDialog's identical action --
  // rather than leaving InputChip.onDeleted's delete icon on its default
  // localized message, which is just "Delete". That default is generic
  // enough to collide with unrelated "Delete" buttons elsewhere in the app
  // (e.g. Object Store's per-object Delete button) since this row's chips
  // live in the persistent top toolbar, mounted across every tab.
  //
  // includeDeleteTooltip: false for the offstage measurement copy (see the
  // key/includeTooltip comment on _buildAddButton below for why offstage
  // copies need their tooltips suppressed) -- an empty string (not null)
  // is required to actually suppress it: null would fall back to the
  // generic localized default instead of no tooltip.
  Widget _buildChip(SubscriptionInfo info, {bool includeDeleteTooltip = true}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: _chipGap),
      child: ColorTabChip(
        color: widget.showSubscriptionColors
            ? resolveSubscriptionColor(info.colorIndex, widget.isDark)
            : null,
        // labelStyle (not a Text.style override) so the chip's own layout
        // math -- which sizes padding around its *assumed* label style --
        // knows about our smaller font and can still center it correctly;
        // a custom Text.style bypasses that and renders visibly off-center.
        chip: InputChip(
          label: Text(_labelFor(info)),
          labelStyle: _labelStyle.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
          backgroundColor: theme.colorScheme.secondaryContainer,
          side: BorderSide.none,
          onPressed: () => widget.onTapChip(info),
          onDeleted: () => widget.onRemoveChip(info),
          deleteIconColor: theme.colorScheme.onSecondaryContainer,
          deleteButtonTooltipMessage:
              includeDeleteTooltip ? 'Remove subscription' : '',
        ),
      ),
    );
  }

  Widget _buildOverflowChip(int count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: _chipGap),
      child: ActionChip(
        label: Text('+$count more'),
        labelStyle: _labelStyle.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
        backgroundColor: theme.colorScheme.secondaryContainer,
        side: BorderSide.none,
        onPressed: widget.onOpenManager,
      ),
    );
  }

  // key: lets callers target the *visible* button specifically -- this is
  // also built a second time inside the invisible offstage measurement pass
  // below, and generic finders (find.byTooltip/find.byType) see both copies
  // regardless of Offstage, since Offstage only affects painting/hit-testing.
  //
  // includeTooltip: false for that same offstage copy. Tooltip installs its
  // bubble via OverlayPortal into the app's shared Overlay independently of
  // its trigger's own offstage/zero-size status -- confirmed empirically:
  // real-window integration tests tapping the *visible* button's exact
  // center intermittently hit stray Overlay/RenderSnapshotWidget render
  // objects instead once the offstage pass had its own "Add subscription"
  // Tooltip. No known functional need for the measurement copy to have a
  // tooltip at all, so simplest fix is to just not give it one.
  Widget _buildAddButton({Key? key, bool includeTooltip = true}) {
    return IconButton.filledTonal(
      key: key,
      icon: const Icon(Icons.add, size: 18),
      tooltip: includeTooltip ? 'Add subscription' : null,
      onPressed: widget.onAdd,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = widget.subscriptions;
    final theme = Theme.of(context);
    _measuredChipWidths.removeWhere((info, _) => !subscriptions.contains(info));

    final widths = subscriptions
        .map((info) => _measuredChipWidths[info] ?? _estimateChipWidth(info))
        .toList();
    final addButtonWidth = _measuredAddButtonWidth ?? _addButtonWidth;
    final overflowWidth = _measuredOverflowWidth ?? _overflowChipWidth;

    // No enclosing box and no divider -- a bordered/outlined container
    // around chips that already carry their own filled shape read as
    // "double-boxed" (chip border nested in field border) and cramped.
    // Grouping instead comes entirely from a fixed inline label (not a
    // floating one, since there's no box for it to float against -- closer
    // to how a mail client's "To" field labels a row of recipient chips).
    return Focus(
      focusNode: _focusNode,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focusNode.requestFocus(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  'Subjects',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final budget = constraints.maxWidth - addButtonWidth - 8;

                  final totalWidth = widths.fold<double>(0, (a, b) => a + b);

                  List<SubscriptionInfo> visible;
                  List<SubscriptionInfo> overflow;
                  if (subscriptions.isEmpty || totalWidth <= budget) {
                    visible = subscriptions;
                    overflow = const [];
                  } else {
                    final fitBudget = budget - overflowWidth;
                    visible = [];
                    var running = 0.0;
                    for (var i = 0; i < subscriptions.length; i++) {
                      running += widths[i];
                      if (running <= fitBudget) {
                        visible.add(subscriptions[i]);
                      } else {
                        break;
                      }
                    }
                    // Always show at least one chip -- an empty row reads as
                    // "no subscriptions", which would be wrong whenever
                    // there's at least one.
                    if (visible.isEmpty) {
                      visible = [subscriptions.first];
                    }
                    overflow = subscriptions.sublist(visible.length);
                  }

                  return Stack(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subscriptions.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(right: _chipGap),
                                child: Text(
                                  'No subscriptions',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            for (final info in visible) _buildChip(info),
                            if (overflow.isNotEmpty)
                              _buildOverflowChip(overflow.length),
                            _buildAddButton(
                                key: const ValueKey('subjectChipsAddButton')),
                          ],
                        ),
                      ),
                      // Invisible measurement pass: every subscription's
                      // real chip, the real add button, and a worst-case
                      // (full count) overflow chip, laid out unconstrained
                      // so each reports its true natural width.
                      //
                      // Positioned with an explicit width/height of 0, not a
                      // plain child: Stack's default sizing (StackFit.loose)
                      // sizes itself to fit *every* non-positioned child, and
                      // Offstage only suppresses paint/hit-testing -- it
                      // doesn't shrink the geometry of whatever wraps it. A
                      // plain child here previously forced the whole Stack
                      // (and with it the entire toolbar row) to be as tall as
                      // this measurement subtree, even though nothing in it
                      // was ever actually painted. Positioned children are
                      // excluded from Stack's own sizing pass entirely.
                      //
                      // The pinned 0x0 size matters for a second, unrelated
                      // reason: RenderConstrainedOverflowBox sizes *itself*
                      // using its own incoming constraints
                      // (constraints.biggest), not the minWidth/minHeight/
                      // maxWidth/maxHeight override params below -- those
                      // only affect what's passed to its *child*. Feeding it
                      // an unbounded incoming constraint (which is what a
                      // bare `Positioned(left: 0, top: 0)` gets from Stack --
                      // no width/height means a loose 0..infinity box) makes
                      // OverflowBox try to report an infinite size for
                      // itself and layout crashes. Pinning both dimensions
                      // to a tight, finite 0x0 here sidesteps that
                      // completely -- the override params below still give
                      // the actual *child* being measured effectively
                      // unconstrained width/height to report its true
                      // natural size, regardless of how small this outer box is.
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 0,
                        height: 0,
                        child: Offstage(
                          offstage: true,
                          child: OverflowBox(
                            minWidth: 0,
                            maxWidth: double.infinity,
                            minHeight: 0,
                            maxHeight: double.infinity,
                            alignment: Alignment.topLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final info in subscriptions)
                                  _MeasureSize(
                                    onChange: (size) =>
                                        _recordChipWidth(info, size.width),
                                    child: _buildChip(info,
                                        includeDeleteTooltip: false),
                                  ),
                                _MeasureSize(
                                  onChange: (size) =>
                                      _recordAddButtonWidth(size.width),
                                  child: _buildAddButton(includeTooltip: false),
                                ),
                                _MeasureSize(
                                  onChange: (size) =>
                                      _recordOverflowWidth(size.width),
                                  child: _buildOverflowChip(
                                      subscriptions.length),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reports its child's real laid-out size via [onChange] whenever it
/// changes. Used to measure chips/buttons precisely instead of guessing
/// from an estimate -- see [SubjectChipsRow]'s doc comment.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const _MeasureSize({required this.onChange, required Widget super.child});

  @override
  _RenderMeasureSize createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
      BuildContext context, _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _oldSize;

  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      onChange(newSize);
    }
  }
}
