import 'package:flutter/material.dart';

class SettingsDialog extends StatefulWidget {
  final double initialFontSize;
  final bool initialSingleLine;
  final int initialRetryInterval;
  final void Function(double, bool, int) onSave;

  const SettingsDialog({
    super.key,
    required this.initialFontSize,
    required this.initialSingleLine,
    required this.initialRetryInterval,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late double tempFontSize;
  late bool tempSingleLine;
  late int tempRetryInterval;

  @override
  void initState() {
    super.initState();
    tempFontSize = widget.initialFontSize;
    tempSingleLine = widget.initialSingleLine;
    tempRetryInterval = widget.initialRetryInterval;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Settings'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Message Font Size'),
              Expanded(
                child: Slider(
                  min: 10,
                  max: 30,
                  divisions: 20,
                  value: tempFontSize,
                  label: tempFontSize.round().toString(),
                  onChanged: (v) {
                    setState(() {
                      tempFontSize = v;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(tempFontSize.round().toString()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Single Line Messages'),
              Switch(
                value: tempSingleLine,
                onChanged: (v) {
                  setState(() {
                    tempSingleLine = v;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Reconnect Interval'),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: tempRetryInterval,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 3, child: Text('3 seconds')),
                    DropdownMenuItem(value: 5, child: Text('5 seconds')),
                    DropdownMenuItem(value: 10, child: Text('10 seconds')),
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      tempRetryInterval = value!;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Save'),
          onPressed: () {
            widget.onSave(tempFontSize, tempSingleLine, tempRetryInterval);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
