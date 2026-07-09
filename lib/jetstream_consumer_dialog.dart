import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

/// Dialog for creating a new consumer on a stream, supporting both push
/// (deliver subject) and pull models.
class CreateConsumerDialog extends StatefulWidget {
  final void Function(ConsumerConfig config) onCreate;

  const CreateConsumerDialog({super.key, required this.onCreate});

  @override
  State<CreateConsumerDialog> createState() => _CreateConsumerDialogState();
}

class _CreateConsumerDialogState extends State<CreateConsumerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _filterSubjectController = TextEditingController();
  final _deliverSubjectController = TextEditingController();
  bool _isPush = false;
  String _ackPolicy = 'explicit';
  String _deliverPolicy = 'all';

  @override
  void dispose() {
    _nameController.dispose();
    _filterSubjectController.dispose();
    _deliverSubjectController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final durable = _nameController.text.trim();
    final filterSubject = _filterSubjectController.text.trim();

    widget.onCreate(ConsumerConfig(
      durable: durable.isEmpty ? null : durable,
      deliverSubject: _isPush ? _deliverSubjectController.text.trim() : null,
      filterSubject: filterSubject.isEmpty ? null : filterSubject,
      ackPolicy: _ackPolicy,
      deliverPolicy: _deliverPolicy,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Create Consumer'),
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
                  labelText: 'Durable Name (optional)',
                  hintText: 'Leave blank for an ephemeral consumer',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _filterSubjectController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Filter Subject (optional)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Push Consumer'),
                  Switch(
                    value: _isPush,
                    onChanged: (v) => setState(() => _isPush = v),
                  ),
                ],
              ),
              if (_isPush) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deliverSubjectController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Deliver Subject',
                  ),
                  validator: (v) => _isPush && (v == null || v.trim().isEmpty)
                      ? 'A deliver subject is required for push consumers.'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _ackPolicy,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Ack Policy',
                ),
                items: const [
                  DropdownMenuItem(value: 'explicit', child: Text('Explicit')),
                  DropdownMenuItem(value: 'none', child: Text('None')),
                  DropdownMenuItem(value: 'all', child: Text('All')),
                ],
                onChanged: (value) => setState(() => _ackPolicy = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _deliverPolicy,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Deliver Policy',
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'last', child: Text('Last')),
                  DropdownMenuItem(value: 'new', child: Text('New')),
                ],
                onChanged: (value) => setState(() => _deliverPolicy = value!),
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
