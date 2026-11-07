import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'format_utils.dart';

/// "↑ 1.2k new" button floating at the top of a message list while the user
/// is scrolled down and new messages are waiting (see the hold behavior in
/// `main.dart`'s `_flushIncomingMessages`). Pressing it jumps to the top,
/// which lets the waiting messages in. Hidden while [count] is 0.
class HeldMessagesPill extends StatelessWidget {
  final ValueListenable<int> count;
  final VoidCallback onPressed;

  const HeldMessagesPill(
      {super.key, required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (context, n, _) {
        if (n == 0) return const SizedBox.shrink();
        return Tooltip(
          message: 'Show new messages',
          child: FilledButton.tonalIcon(
            key: const ValueKey('heldMessagesPill'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              elevation: 2,
            ),
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_upward, size: 16),
            label: Text('${formatCompactCount(n)} new'),
          ),
        );
      },
    );
  }
}
