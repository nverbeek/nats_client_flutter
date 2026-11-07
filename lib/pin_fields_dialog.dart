import 'package:flutter/material.dart';

import 'message_font.dart';
import 'pinned_fields.dart';

/// "Pin Fields" picker, opened from a message row: lists every field in that
/// message (arrays of objects merged as `[*]`) with a sample value, so a
/// field can be pinned by clicking it rather than typing its path.
///
/// [pinned] are the current pinned sources (possibly `name=path`). Fields
/// pinned but absent from this message are listed too, so they can be
/// unchecked here. [onSave] gets the new list: existing pins keep their
/// order and short names, new picks are appended in message order.
class PinFieldsDialog extends StatefulWidget {
  final String subject;
  final Object json;
  final List<String> pinned;
  final void Function(List<String> sources) onSave;

  const PinFieldsDialog({
    super.key,
    required this.subject,
    required this.json,
    required this.pinned,
    required this.onSave,
  });

  @override
  State<PinFieldsDialog> createState() => _PinFieldsDialogState();
}

class _PinFieldsDialogState extends State<PinFieldsDialog> {
  late final List<String> _messagePaths;
  late final List<String> _otherPinnedPaths;
  late final Set<String> _checked;
  final TextEditingController _search = TextEditingController();

  static String _pathOf(String source) =>
      parsePinnedPath(source)?.path ?? source;

  @override
  void initState() {
    super.initState();
    _messagePaths = flattenJsonPaths(widget.json);
    final pinnedPaths = widget.pinned.map(_pathOf).toList();
    _otherPinnedPaths =
        pinnedPaths.where((p) => !_messagePaths.contains(p)).toList();
    _checked = pinnedPaths.toSet();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _result() {
    final kept =
        widget.pinned.where((s) => _checked.contains(_pathOf(s))).toList();
    final keptPaths = kept.map(_pathOf).toSet();
    return [
      ...kept,
      ..._messagePaths
          .where((p) => _checked.contains(p) && !keptPaths.contains(p)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.text.toLowerCase();
    final rows = [..._messagePaths, ..._otherPinnedPaths]
        .where((p) => p.toLowerCase().contains(query))
        .toList();
    final count = _checked.length;
    return AlertDialog(
      title: const Text('Pin Fields'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From a message on ${widget.subject}. Pinned fields show at '
              'the start of every row that has them.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pinFieldsSearch'),
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search fields',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No fields match.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _row(rows[i], theme),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_result());
            Navigator.of(context).pop();
          },
          child: Text(count == 0
              ? 'Clear Pins'
              : 'Pin $count Field${count == 1 ? '' : 's'}'),
        ),
      ],
    );
  }

  Widget _row(String path, ThemeData theme) {
    final parsed = parsePinnedPath(path);
    final value = parsed == null ? null : extractPinned(widget.json, parsed);
    final mono = pinValueStyle(color: theme.colorScheme.onSurface)
        .copyWith(fontSize: 13);
    return CheckboxListTile(
      key: ValueKey('pinFieldsRow_$path'),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: _checked.contains(path),
      onChanged: (checked) => setState(() {
        if (checked ?? false) {
          _checked.add(path);
        } else {
          _checked.remove(path);
        }
      }),
      title: Row(
        children: [
          Expanded(
            child: Text(path,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.display ?? 'not in this message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: value == null
                  ? theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant)
                  : mono.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
