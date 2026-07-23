import 'package:flutter/material.dart';

/// Small prompt for how long to pause a consumer (NATS 2.11+, `dart_nats`
/// 1.3.0's `JetStream.pauseConsumer`). Pops a [Duration] on submit, or `null`
/// if cancelled -- the caller computes `pauseUntil` as `DateTime.now().add(duration)`
/// at the moment the request is actually sent, not here.
class ConsumerPauseDurationDialog extends StatefulWidget {
  final String consumerName;

  const ConsumerPauseDurationDialog({super.key, required this.consumerName});

  @override
  State<ConsumerPauseDurationDialog> createState() =>
      _ConsumerPauseDurationDialogState();
}

class _ConsumerPauseDurationDialogState
    extends State<ConsumerPauseDurationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _minutesController = TextEditingController(text: '5');

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final minutes = int.parse(_minutesController.text.trim());
    Navigator.of(context).pop(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pause "${widget.consumerName}"?'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Message delivery/pulls are suspended until the pause '
                  'expires or the consumer is resumed.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Pause for how many minutes',
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 1) return 'Enter a positive integer.';
                  return null;
                },
              ),
            ],
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
          child: const Text('Pause'),
        ),
      ],
    );
  }
}
