import 'package:flutter/material.dart';

class SettingsDialog extends StatefulWidget {
  final double initialFontSize;
  final bool initialSingleLine;
  final void Function(double, bool) onSave;

  const SettingsDialog({
    super.key,
    required this.initialFontSize,
    required this.initialSingleLine,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late double tempFontSize;
  late bool tempSingleLine;

  @override
  void initState() {
    super.initState();
    tempFontSize = widget.initialFontSize;
    tempSingleLine = widget.initialSingleLine;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
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
            widget.onSave(tempFontSize, tempSingleLine);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
