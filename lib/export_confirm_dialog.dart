import 'package:flutter/material.dart';

import 'message_export.dart';

/// One-shot confirmation dialog for Export ("Export Selected"/"Export
/// All"), mirroring the app's existing delete/purge confirmation shell
/// (e.g. `JetStreamDashboard._confirmDeleteStream`) but with computed
/// content text showing the real message count -- warn-and-proceed past
/// [largeExportWarningThreshold], never a silent hard cap.
///
/// The actual file write isn't done here -- [onConfirm] is a plain
/// callback, matching how `CreateStreamDialog.onCreate`/
/// `SendMessageDialog.onSend` hand work back to the caller.
class ExportConfirmDialog extends StatelessWidget {
  final int count;
  final String sourceLabel;
  final VoidCallback onConfirm;

  const ExportConfirmDialog({
    super.key,
    required this.count,
    required this.sourceLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final isLarge = count > largeExportWarningThreshold;
    return AlertDialog(
      title: const Text('Export Messages?'),
      content: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Export $count $sourceLabel message(s) to a file?'),
            if (isLarge)
              const TextSpan(
                text: '\n\nThis is a large export and may take a moment '
                    'to prepare and write to disk.',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            onConfirm();
            Navigator.of(context).pop();
          },
          child: const Text('Export'),
        ),
      ],
    );
  }
}
