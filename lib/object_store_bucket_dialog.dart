import 'package:flutter/material.dart';

/// Dialog for creating a new Object Store bucket. Mirrors
/// `kv_bucket_dialog.dart`'s `CreateBucketDialog` shape, swapping "History
/// Depth" (not applicable to Object Store, which keeps one live revision per
/// object) for a storage-type choice and an optional max-size cap.
class CreateObjectStoreBucketDialog extends StatefulWidget {
  final void Function(String bucket, String storage, int replicas, int maxBytes,
      Duration? ttl) onCreate;

  const CreateObjectStoreBucketDialog({super.key, required this.onCreate});

  @override
  State<CreateObjectStoreBucketDialog> createState() =>
      _CreateObjectStoreBucketDialogState();
}

class _CreateObjectStoreBucketDialogState
    extends State<CreateObjectStoreBucketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _maxSizeController = TextEditingController();
  final _ttlController = TextEditingController();
  String _storage = 'file';
  int _replicas = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _maxSizeController.dispose();
    _ttlController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final maxSizeMb = int.tryParse(_maxSizeController.text.trim());
    final ttlDays = int.tryParse(_ttlController.text.trim());

    widget.onCreate(
      _nameController.text.trim(),
      _storage,
      _replicas,
      (maxSizeMb != null && maxSizeMb > 0) ? maxSizeMb * 1024 * 1024 : -1,
      ttlDays != null && ttlDays > 0 ? Duration(days: ttlDays) : null,
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
              TextFormField(
                controller: _maxSizeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Max Size (MB, optional)',
                  hintText: 'Leave blank for unlimited',
                ),
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
