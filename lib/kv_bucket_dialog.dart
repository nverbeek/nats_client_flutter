import 'package:flutter/material.dart';

/// Dialog for creating a new KV bucket. Mirrors `CreateStreamDialog`'s
/// shape/pattern, exposing the handful of settings a user is likely to want
/// up-front (name, history depth, TTL, replicas) rather than every possible
/// stream knob.
class CreateBucketDialog extends StatefulWidget {
  final void Function(String bucket, int history, Duration? ttl, int replicas)
      onCreate;

  const CreateBucketDialog({super.key, required this.onCreate});

  @override
  State<CreateBucketDialog> createState() => _CreateBucketDialogState();
}

class _CreateBucketDialogState extends State<CreateBucketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _historyController = TextEditingController(text: '1');
  final _ttlController = TextEditingController();
  int _replicas = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _historyController.dispose();
    _ttlController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final history = int.tryParse(_historyController.text.trim()) ?? 1;
    final ttlDays = int.tryParse(_ttlController.text.trim());

    widget.onCreate(
      _nameController.text.trim(),
      history < 1 ? 1 : history,
      ttlDays != null && ttlDays > 0 ? Duration(days: ttlDays) : null,
      _replicas,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Create Bucket'),
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
                  labelText: 'Bucket Name',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'A bucket name is required.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _historyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'History Depth',
                  hintText: 'Revisions kept per key',
                ),
                validator: (v) {
                  final parsed = int.tryParse((v ?? '').trim());
                  return (parsed == null || parsed < 1)
                      ? 'Enter a whole number of at least 1.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ttlController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'TTL (days, optional)',
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
