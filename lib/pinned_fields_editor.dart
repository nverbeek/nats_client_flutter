import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'message_font.dart';
import 'pinned_fields.dart';

/// Chip editor for the pinned-field list in Settings: each pinned path is a
/// chip with a remove button; typing a path and pressing Enter (or a comma)
/// adds it, and Backspace in the empty input removes the last chip.
class PinnedFieldsEditor extends StatefulWidget {
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  /// Reports whether the input holds text that isn't a valid path, so the
  /// dialog can hold Save until it's fixed or cleared.
  final ValueChanged<bool> onPendingErrorChanged;

  const PinnedFieldsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onPendingErrorChanged,
  });

  @override
  State<PinnedFieldsEditor> createState() => PinnedFieldsEditorState();
}

class PinnedFieldsEditorState extends State<PinnedFieldsEditor> {
  late List<String> _pins;
  final TextEditingController _input = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  String? _error;

  @override
  void initState() {
    super.initState();
    _pins = List.of(widget.initial);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Adds whatever is typed in the input (comma-separated paths). Returns
  /// false, and shows an error, if any of it isn't a valid path.
  bool commitPending() {
    final parts = _input.text
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      _setError(null);
      return true;
    }
    final bad = parts.where((p) => parsePinnedPath(p) == null).toList();
    if (bad.isNotEmpty) {
      _setError('Can\'t read "${bad.first}". Use dots for keys and [n] or '
          '[*] for arrays.');
      return false;
    }
    setState(() {
      for (final p in parts) {
        if (!_pins.contains(p)) _pins.add(p);
      }
      _input.clear();
    });
    _setError(null);
    widget.onChanged(List.of(_pins));
    return true;
  }

  void _setError(String? error) {
    if (error == _error) return;
    setState(() => _error = error);
    widget.onPendingErrorChanged(error != null);
  }

  // Backspace in the empty input removes the last chip. On the field's own
  // focus node, so it runs before the text field's editing shortcuts.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _input.text.isEmpty &&
        _pins.isNotEmpty) {
      _remove(_pins.length - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _remove(int index) {
    setState(() => _pins.removeAt(index));
    widget.onChanged(List.of(_pins));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = pinValueStyle(color: theme.colorScheme.onSurface)
        .copyWith(fontSize: 13);
    return InputDecorator(
      isFocused: _focus.hasFocus,
      decoration: InputDecoration(
        labelText: 'JSON Paths',
        border: const OutlineInputBorder(),
        helperText: 'JSON paths shown at the start of each row, e.g. label, '
            'meta.status, items[*].sku, fc=fulfillment_center_id (short '
            'name). Or use Pin Fields… on any message.',
        helperMaxLines: 3,
        errorText: _error,
        errorMaxLines: 2,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < _pins.length; i++)
            InputChip(
              key: ValueKey('pinnedFieldChip_${_pins[i]}'),
              label: Text(_pins[i], style: mono),
              onDeleted: () => _remove(i),
              deleteButtonTooltipMessage: 'Remove ${_pins[i]}',
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
            child: IntrinsicWidth(
              child: TextField(
                key: const ValueKey('pinnedFieldsInput'),
                controller: _input,
                focusNode: _focus,
                style: mono,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Add a path, then Enter',
                ),
                onChanged: (text) {
                  if (text.endsWith(',')) {
                    commitPending();
                  } else if (_error != null) {
                    _setError(null);
                  }
                },
                onSubmitted: (_) {
                  commitPending();
                  _focus.requestFocus();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
