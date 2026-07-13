import 'package:flutter/material.dart';

class SettingsDialog extends StatefulWidget {
  final double initialFontSize;
  final int initialRetryInterval;
  final bool initialJetStreamEnabled;
  final bool initialKvEnabled;
  final bool initialObjectStoreEnabled;
  final bool initialUpdateCheckEnabled;
  final void Function(double, int, bool, bool, bool, bool) onSave;

  const SettingsDialog({
    super.key,
    required this.initialFontSize,
    required this.initialRetryInterval,
    required this.initialJetStreamEnabled,
    required this.initialKvEnabled,
    required this.initialObjectStoreEnabled,
    required this.initialUpdateCheckEnabled,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late double tempFontSize;
  late int tempRetryInterval;
  late bool tempJetStreamEnabled;
  late bool tempKvEnabled;
  late bool tempObjectStoreEnabled;
  late bool tempUpdateCheckEnabled;

  @override
  void initState() {
    super.initState();
    tempFontSize = widget.initialFontSize;
    tempRetryInterval = widget.initialRetryInterval;
    tempJetStreamEnabled = widget.initialJetStreamEnabled;
    tempKvEnabled = widget.initialKvEnabled;
    tempObjectStoreEnabled = widget.initialObjectStoreEnabled;
    tempUpdateCheckEnabled = widget.initialUpdateCheckEnabled;
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
      content: SingleChildScrollView(
        child: Column(
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
              children: [
                const Text('Reconnect Interval'),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: tempRetryInterval,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Enable JetStream'),
                Switch(
                  value: tempJetStreamEnabled,
                  onChanged: (v) {
                    setState(() {
                      tempJetStreamEnabled = v;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Enable Key-Value Stores'),
                Switch(
                  value: tempKvEnabled,
                  onChanged: (v) {
                    setState(() {
                      tempKvEnabled = v;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Enable Object Store'),
                Switch(
                  value: tempObjectStoreEnabled,
                  onChanged: (v) {
                    setState(() {
                      tempObjectStoreEnabled = v;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Check for Updates'),
                Switch(
                  value: tempUpdateCheckEnabled,
                  onChanged: (v) {
                    setState(() {
                      tempUpdateCheckEnabled = v;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
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
            widget.onSave(
                tempFontSize,
                tempRetryInterval,
                tempJetStreamEnabled,
                tempKvEnabled,
                tempObjectStoreEnabled,
                tempUpdateCheckEnabled);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
