import 'package:flutter/material.dart';

/// Wraps a chip [child] with a small color tab that protrudes past its own
/// left edge, like a colored bookmark peeking out from behind the pill.
/// Shared by [SubjectChipsRow]'s toolbar chips and
/// [SubscriptionManagerDialog]'s subscription list so both use identical
/// protrusion/corner-radius math instead of drifting apart.
class ColorTabChip extends StatelessWidget {
  // Matches Material 3's InputChip/Chip default shape (RoundedRectangleBorder,
  // radius 8 -- see _ChipDefaultsM3 in the Flutter SDK's chip.dart) so the
  // tab's outer corners blend with the chip's own corners instead of looking
  // mismatched.
  static const double cornerRadius = 8;
  // How far the tab pokes out past the chip's left edge.
  static const double tabProtrusion = 4;
  // Total tab width: protrusion + enough hidden underneath the chip to clear
  // its rounded corner (so the chip's curve never exposes a straight edge of
  // the tab beneath it).
  static const double _tabWidth = tabProtrusion + cornerRadius;

  final Color? color;
  final Widget chip;

  const ColorTabChip({super.key, required this.color, required this.chip});

  @override
  Widget build(BuildContext context) {
    // No color means the tab is turned off entirely (see the "Show
    // Subscription Colors" setting) -- return the chip as-is rather than
    // painting a transparent tab, so no space is reserved for it.
    final color = this.color;
    if (color == null) return chip;

    return Padding(
      // Reserves room for the tab to protrude into -- without this, painting
      // outside the chip's own bounds (via Clip.none below) would get
      // clipped by whatever scrollable/clipping ancestor the chip sits in.
      padding: const EdgeInsets.only(left: tabProtrusion),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted first so the chip (painted on top) covers everything but
          // its protruding sliver.
          Positioned(
            left: -tabProtrusion,
            top: 0,
            bottom: 0,
            width: _tabWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(cornerRadius),
                  bottomLeft: Radius.circular(cornerRadius),
                ),
              ),
            ),
          ),
          chip,
        ],
      ),
    );
  }
}
