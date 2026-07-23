import 'package:flutter/material.dart';

import 'format_utils.dart' show isValidNatsSubjectFilter;

/// Which of the mutually-exclusive purge scopes (per the server's own
/// `$JS.API.STREAM.PURGE` API) the dialog is currently configured for.
enum PurgeScope { all, keepNewest, upToSequence }

/// Confirmation + options dialog for purging a stream, replacing the old
/// bare "Purge everything, yes/no?" confirm with the `filter`/`keep`/`seq`
/// options `dart_nats` 1.4.0's `JsStream.purge()` added. Defaults to the
/// original all-or-nothing behavior ([PurgeScope.all], no filter) so the
/// common case is unchanged -- one Cancel/Purge tap, no extra fields to fill in.
class PurgeStreamDialog extends StatefulWidget {
  final String streamName;
  final void Function({String? filter, int? keep, int? seq}) onSubmit;

  const PurgeStreamDialog({
    super.key,
    required this.streamName,
    required this.onSubmit,
  });

  @override
  State<PurgeStreamDialog> createState() => _PurgeStreamDialogState();
}

class _PurgeStreamDialogState extends State<PurgeStreamDialog> {
  final _formKey = GlobalKey<FormState>();
  final _filterController = TextEditingController();
  final _keepController = TextEditingController();
  final _seqController = TextEditingController();
  PurgeScope _scope = PurgeScope.all;

  @override
  void dispose() {
    _filterController.dispose();
    _keepController.dispose();
    _seqController.dispose();
    super.dispose();
  }

  String get _warningText {
    switch (_scope) {
      case PurgeScope.all:
        return 'This permanently deletes all messages in "${widget.streamName}" '
            '(or, if a subject filter is set below, all messages matching it). '
            'This cannot be undone.';
      case PurgeScope.keepNewest:
        return 'This permanently deletes all but the newest N messages in '
            '"${widget.streamName}" (restricted to the subject filter below, '
            'if set). This cannot be undone.';
      case PurgeScope.upToSequence:
        return 'This permanently deletes every message in "${widget.streamName}" '
            'up to (but not including) the given sequence number (restricted '
            'to the subject filter below, if set). This cannot be undone.';
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final filter = _filterController.text.trim();
    int? keep;
    int? seq;
    if (_scope == PurgeScope.keepNewest) {
      keep = int.parse(_keepController.text.trim());
    } else if (_scope == PurgeScope.upToSequence) {
      seq = int.parse(_seqController.text.trim());
    }
    Navigator.of(context).pop();
    widget.onSubmit(filter: filter.isEmpty ? null : filter, keep: keep, seq: seq);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Purge Stream?'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_warningText),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _filterController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Subject Filter (optional)',
                    hintText: 'e.g. orders.cancelled',
                  ),
                  validator: (v) {
                    final trimmed = v?.trim() ?? '';
                    if (trimmed.isEmpty) return null;
                    return isValidNatsSubjectFilter(trimmed)
                        ? null
                        : 'Not a valid NATS subject.';
                  },
                ),
                const SizedBox(height: 16),
                SegmentedButton<PurgeScope>(
                  segments: const [
                    ButtonSegment(value: PurgeScope.all, label: Text('All')),
                    ButtonSegment(
                        value: PurgeScope.keepNewest,
                        label: Text('Keep Newest')),
                    ButtonSegment(
                        value: PurgeScope.upToSequence,
                        label: Text('Up to Seq')),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (selection) =>
                      setState(() => _scope = selection.first),
                ),
                if (_scope == PurgeScope.keepNewest) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _keepController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Keep newest N messages',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n < 1) {
                        return 'Enter a positive integer.';
                      }
                      return null;
                    },
                  ),
                ],
                if (_scope == PurgeScope.upToSequence) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _seqController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Purge up to sequence',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n < 1) {
                        return 'Enter a positive integer.';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
          child: const Text('Purge'),
        ),
      ],
    );
  }
}
