import 'package:flutter/material.dart';

/// The label color, background, and border every "subject chip" in this app
/// shares: subscription chips (`SubjectChipsRow`, `SubscriptionManagerDialog`)
/// and JetStream's stream-subject chips (`JetStreamDashboard`). Kept as
/// static accessors rather than a single widget/builder function because
/// `Chip`, `InputChip`, and `ActionChip` don't share a common constructor to
/// build from one place -- callers apply these to whichever chip type they
/// need.
class SubjectChipStyle {
  SubjectChipStyle._();

  static const double labelFontSize = 13;

  static Color foregroundColorFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSecondaryContainer;

  static TextStyle labelStyleFor(BuildContext context) =>
      TextStyle(fontSize: labelFontSize, color: foregroundColorFor(context));

  static Color backgroundColorFor(BuildContext context) =>
      Theme.of(context).colorScheme.secondaryContainer;

  static const BorderSide side = BorderSide.none;
}
