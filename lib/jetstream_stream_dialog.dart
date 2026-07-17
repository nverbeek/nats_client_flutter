import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'format_utils.dart';

/// Dialog for creating a new JetStream stream. Only exposes the handful of
/// [StreamConfig] fields a user is likely to want to set up-front (name,
/// subjects, max age, replicas) — everything else keeps the package's
/// defaults ('file' storage, 'limits' retention, unlimited size).
class CreateStreamDialog extends StatefulWidget {
  final void Function(StreamConfig config) onCreate;

  const CreateStreamDialog({super.key, required this.onCreate});

  @override
  State<CreateStreamDialog> createState() => _CreateStreamDialogState();
}

class _CreateStreamDialogState extends State<CreateStreamDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subjectsController = TextEditingController();
  final _maxAgeController = TextEditingController();
  int _replicas = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _subjectsController.dispose();
    _maxAgeController.dispose();
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

    widget.onCreate(StreamConfig(
      name: _nameController.text.trim(),
      subjects: subjects,
      numReplicas: _replicas,
      maxAge: maxAgeDays != null && maxAgeDays > 0
          ? Duration(days: maxAgeDays)
          : null,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Create Stream'),
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Stream Name',
                ),
                validator: (v) {
                  final trimmed = v?.trim() ?? '';
                  if (trimmed.isEmpty) return 'A stream name is required.';
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
            ],
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}
