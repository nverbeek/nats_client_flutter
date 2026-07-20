import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format_utils.dart';

class _PutIntent extends Intent {
  const _PutIntent();
}

/// Dialog for creating a new key or editing an existing one. When
/// [existingRevision] is set, the key field is locked and the save callback
/// includes that revision so the caller can do an optimistic-concurrency
/// `update()` rather than a blind `put()` — this is what lets a stale edit
/// (someone else changed the key after this dialog loaded it) be caught
/// instead of silently overwritten.
class KvPutValueDialog extends StatefulWidget {
  final String bucket;
  final String? initialKey;
  final String? initialValue;
  final int? existingRevision;
  final void Function(String key, String value, int? expectedRevision) onSave;

  const KvPutValueDialog({
    super.key,
    required this.bucket,
    this.initialKey,
    this.initialValue,
    this.existingRevision,
    required this.onSave,
  });

  @override
  State<KvPutValueDialog> createState() => _KvPutValueDialogState();
}

class _KvPutValueDialogState extends State<KvPutValueDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;

  bool get _isEdit => widget.existingRevision != null;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initialKey ?? '');
    _valueController = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(_keyController.text.trim(), _valueController.text,
        widget.existingRevision);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const _PutIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter):
            const _PutIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PutIntent: CallbackAction<_PutIntent>(
            onInvoke: (_PutIntent intent) {
              _save();
              return null;
            },
          ),
        },
        child: AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_isEdit ? 'Edit Value' : 'Put Value'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 320,
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Text('Bucket: ${widget.bucket}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _keyController,
                    enabled: !_isEdit,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Key',
                      labelText: 'Key',
                    ),
                    validator: (v) {
                      final trimmed = v?.trim() ?? '';
                      if (trimmed.isEmpty) return 'A key is required.';
                      if (!isValidLiteralNatsSubject(trimmed)) {
                        return 'Keys can\'t contain *, >, whitespace, or empty segments.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _valueController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Value',
                        labelText: 'Value',
                      ),
                    ),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Revision #${widget.existingRevision} — save will fail '
                        'if the key changed since it was loaded.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Tooltip(
              message: 'Hint: Ctrl+Enter (Cmd+Enter on Mac) to save',
              child: TextButton(
                onPressed: _save,
                child: Text(_isEdit ? 'Save' : 'Put'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
