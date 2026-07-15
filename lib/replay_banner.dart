import 'package:flutter/material.dart';

import 'format_utils.dart';

/// Slim banner shown directly above the message list while a file-based
/// Replay is running, mirroring `PausedBanner`'s exact shell/placement.
///
/// Deliberately placed outside the `ListView` it sits above (a sibling in
/// the enclosing `Column`, never a list item) so it never interacts with
/// that list's fixed-`itemExtent` scroll-position-stability math -- same
/// reasoning as `PausedBanner`'s own doc comment.
///
/// Deliberately kept separate from `PausedBanner` rather than merged into
/// it: Pause (does the list *render* new arrivals) and Replay (is the app
/// currently *publishing* outgoing messages) are orthogonal, so both
/// banners can legitimately be visible at once.
class ReplayBanner extends StatelessWidget {
  final int sentCount;
  final int totalCount;
  final int currentPass;
  final int totalPasses;
  final VoidCallback onStop;

  const ReplayBanner({
    super.key,
    required this.sentCount,
    required this.totalCount,
    required this.currentPass,
    required this.totalPasses,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline,
                size: 18, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Replaying ${formatGroupedCount(sentCount)}/${formatGroupedCount(totalCount)} '
                '(repeat $currentPass/$totalPasses)',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: onStop,
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}
