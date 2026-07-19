import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'format_utils.dart';

/// Dialog for creating a new JetStream stream, or editing an existing one's
/// configuration when [initial] is supplied. Exposes the full set of
/// [StreamConfig] fields `dart_nats` supports -- storage type, retention
/// policy, discard policy, size/count limits, and the allow-rollup/deny-
/// delete/deny-purge flags -- rather than just name/subjects/maxAge/replicas.
///
/// In edit mode the stream name can't be changed (`$JS.API.STREAM.UPDATE`
/// addresses the stream by its existing name), so the Name field is
/// disabled. Everything else is submitted as a full [StreamConfig] replacing
/// the stream's current configuration -- not merged field-by-field -- so
/// [initial] should come from a fresh, fully-populated fetch (see
/// `JetStreamManager.streamDetail`) rather than a partial snapshot, or
/// unset fields could get reset to their defaults server-side.
class StreamConfigDialog extends StatefulWidget {
  final StreamConfig? initial;
  final void Function(StreamConfig config) onSubmit;

  const StreamConfigDialog({super.key, this.initial, required this.onSubmit});

  bool get isEdit => initial != null;

  @override
  State<StreamConfigDialog> createState() => _StreamConfigDialogState();
}

class _StreamConfigDialogState extends State<StreamConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController =
      TextEditingController(text: widget.initial?.name ?? '');
  late final _subjectsController =
      TextEditingController(text: (widget.initial?.subjects ?? []).join(', '));
  late final _maxAgeController = TextEditingController(
      text: widget.initial?.maxAge != null
          ? widget.initial!.maxAge!.inDays.toString()
          : '');
  late final _maxMsgsController = TextEditingController(
      text: (widget.initial != null && widget.initial!.maxMsgs != -1)
          ? widget.initial!.maxMsgs.toString()
          : '');
  late final _maxBytesController = TextEditingController(
      text: (widget.initial != null && widget.initial!.maxBytes != -1)
          ? widget.initial!.maxBytes.toString()
          : '');
  late final _maxMsgSizeController =
      TextEditingController(text: widget.initial?.maxMsgSize?.toString() ?? '');
  late final _maxMsgsPerSubjectController = TextEditingController(
      text: widget.initial?.maxMsgsPerSubject?.toString() ?? '');

  late int _replicas = widget.initial?.numReplicas ?? 1;
  late String _storage = widget.initial?.storage ?? 'file';
  late String _retention = widget.initial?.retention ?? 'limits';
  late String? _discard = widget.initial?.discard;
  late bool _allowRollup = widget.initial?.allowRollup ?? false;
  late bool _denyDelete = widget.initial?.denyDelete ?? false;
  late bool _denyPurge = widget.initial?.denyPurge ?? false;

  @override
  void dispose() {
    _nameController.dispose();
    _subjectsController.dispose();
    _maxAgeController.dispose();
    _maxMsgsController.dispose();
    _maxBytesController.dispose();
    _maxMsgSizeController.dispose();
    _maxMsgsPerSubjectController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final subjects = _subjectsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final maxAgeDays = int.tryParse(_maxAgeController.text.trim());
    final maxMsgs = int.tryParse(_maxMsgsController.text.trim());
    final maxBytes = int.tryParse(_maxBytesController.text.trim());
    final maxMsgSize = int.tryParse(_maxMsgSizeController.text.trim());
    final maxMsgsPerSubject =
        int.tryParse(_maxMsgsPerSubjectController.text.trim());

    widget.onSubmit(StreamConfig(
      name: widget.isEdit ? widget.initial!.name : _nameController.text.trim(),
      subjects: subjects,
      storage: _storage,
      retention: _retention,
      maxMsgs: maxMsgs ?? -1,
      maxBytes: maxBytes ?? -1,
      discard: _discard,
      maxMsgsPerSubject: maxMsgsPerSubject,
      maxMsgSize: maxMsgSize,
      maxAge: maxAgeDays != null && maxAgeDays > 0
          ? Duration(days: maxAgeDays)
          : null,
      numReplicas: _replicas,
      allowRollup: _allowRollup,
      denyDelete: _denyDelete,
      denyPurge: _denyPurge,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEdit;
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(isEdit ? 'Edit Stream' : 'Create Stream'),
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
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !isEdit,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Stream Name',
                    helperText:
                        isEdit ? 'Stream names can\'t be changed.' : null,
                  ),
                  validator: (v) {
                    if (isEdit) return null;
                    final trimmed = v?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'A stream name is required.';
                    }
                    if (!isValidNatsName(trimmed)) {
                      return 'Stream names can\'t contain ., *, >, or whitespace.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subjectsController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Subjects (comma-separated)',
                    hintText: 'orders.*, orders.>',
                  ),
                  validator: (v) {
                    final subjects = (v ?? '')
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    if (subjects.isEmpty) {
                      return 'At least one subject is required.';
                    }
                    if (subjects.any((s) => !isValidNatsSubjectFilter(s))) {
                      return 'Subjects must be valid NATS subjects (e.g. orders.*, orders.>).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _storage,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Storage',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'file', child: Text('File')),
                    DropdownMenuItem(value: 'memory', child: Text('Memory')),
                  ],
                  onChanged: (value) => setState(() => _storage = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _retention,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Retention Policy',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'limits', child: Text('Limits')),
                    DropdownMenuItem(
                        value: 'interest', child: Text('Interest')),
                    DropdownMenuItem(
                        value: 'workqueue', child: Text('Work Queue')),
                  ],
                  onChanged: (value) => setState(() => _retention = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _discard,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Discard Policy',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Default')),
                    DropdownMenuItem(value: 'old', child: Text('Old')),
                    DropdownMenuItem(value: 'new', child: Text('New')),
                  ],
                  onChanged: (value) => setState(() => _discard = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxAgeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Max Age (days, optional)',
                    hintText: 'Leave blank for unlimited',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxMsgsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Max Messages (optional)',
                    hintText: 'Leave blank for unlimited',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxBytesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Max Bytes (optional)',
                    hintText: 'Leave blank for unlimited',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxMsgSizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Max Message Size (bytes, optional)',
                    hintText: 'Leave blank for unlimited',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxMsgsPerSubjectController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Max Messages Per Subject (optional)',
                    hintText: 'Leave blank for unlimited',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _replicas,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Replicas',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 5, child: Text('5')),
                  ],
                  onChanged: (value) => setState(() => _replicas = value!),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow Rollup Headers'),
                  value: _allowRollup,
                  onChanged: (v) => setState(() => _allowRollup = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Deny Delete'),
                  value: _denyDelete,
                  onChanged: (v) => setState(() => _denyDelete = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Deny Purge'),
                  value: _denyPurge,
                  onChanged: (v) => setState(() => _denyPurge = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
