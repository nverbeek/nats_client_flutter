import 'package:flutter/material.dart';

import 'format_utils.dart';

/// Slim banner shown directly above a paused message list, in the exact
/// spot where the list looks frozen -- easier to notice than only the
/// toolbar's Pause/Resume button changing icon.
///
/// Deliberately placed outside the `ListView` it sits above (a sibling in
/// the enclosing `Column`, never a list item) so it never interacts with
/// that list's fixed-`itemExtent` scroll-position-stability math.
class PausedBanner extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onResume;

  const PausedBanner({
    super.key,
    required this.pendingCount,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countLabel = pendingCount > 0
        ? '${formatCompactCount(pendingCount)} new message${pendingCount == 1 ? '' : 's'} buffered'
        : 'no new messages yet';
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline,
                size: 18, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Paused — $countLabel',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: onResume,
              child: const Text('Resume'),
            ),
          ],
        ),
      ),
    );
  }
}
