import 'package:flutter/material.dart';

import 'jetstream_manager.dart' show describeJetStreamError, formatBytes;
import 'kv_manager.dart' show KvBucketStatus;

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

/// Read-only dialog showing a KV bucket's history depth, storage type,
/// TTL, replica count, and live size/value count -- see
/// `KvManager.bucketStatus`. Mirrors `AccountInfoDialog`'s
/// initial-snapshot-plus-manual-refresh shape.
class KvBucketStatusDialog extends StatefulWidget {
  final String bucket;
  final Future<KvBucketStatus> Function() onRefresh;

  const KvBucketStatusDialog(
      {super.key, required this.bucket, required this.onRefresh});

  @override
  State<KvBucketStatusDialog> createState() => _KvBucketStatusDialogState();
}

class _KvBucketStatusDialogState extends State<KvBucketStatusDialog> {
  KvBucketStatus? _status;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeJetStreamError(e);
        _loading = false;
      });
    }
  }

  Widget _buildContent() {
    if (_loading && _status == null) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _status == null) {
      return Text(_error!);
    }

    final status = _status!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Storage: ${status.storage}'),
        Text('History Depth: ${status.history}'),
        Text(
          'TTL: ${status.ttl == null ? 'unlimited' : '${status.ttl!.inDays} days'}',
        ),
        Text('Replicas: ${status.replicas}'),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Text('Values: ${status.values}'),
        Text('Size: ${formatBytes(status.size)}'),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('Bucket Info: ${widget.bucket}')),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh bucket info',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      content: SizedBox(width: 320, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
