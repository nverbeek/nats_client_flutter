import 'package:flutter/material.dart';

/// Options offered by the "Max Messages Kept" dropdown, in display order.
/// `0` is a sentinel meaning unlimited. If a persisted value isn't in this
/// list (e.g. it was set by a future version, or migrated oddly), the
/// dialog adds it as an extra item on the fly -- see
/// `_SettingsDialogState.initState` -- rather than asserting.
const List<int> maxMessagesOptions = [
  1000,
  5000,
  10000,
  25000,
  50000,
  100000,
  0
];

class SettingsDialog extends StatefulWidget {
  final double initialFontSize;
  final int initialRetryInterval;
  final bool initialJetStreamEnabled;
  final bool initialKvEnabled;
  final bool initialObjectStoreEnabled;
  final bool initialServiceDiscoveryEnabled;
  final bool initialUpdateCheckEnabled;
  final bool initialShowSubscriptionColors;
  final int initialMaxMessages;
  final bool initialShowTimestamps;
  final void Function(double, int, bool, bool, bool, bool, bool, bool, int,
      bool) onSave;

  const SettingsDialog({
    super.key,
    required this.initialFontSize,
    required this.initialRetryInterval,
    required this.initialJetStreamEnabled,
    required this.initialKvEnabled,
    required this.initialObjectStoreEnabled,
    required this.initialServiceDiscoveryEnabled,
    required this.initialUpdateCheckEnabled,
    required this.initialShowSubscriptionColors,
    required this.initialMaxMessages,
    required this.initialShowTimestamps,
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
  late bool tempServiceDiscoveryEnabled;
  late bool tempUpdateCheckEnabled;
  late bool tempShowSubscriptionColors;
  late int tempMaxMessages;
  late bool tempShowTimestamps;
  // maxMessagesOptions plus, if needed, the persisted value -- so a value
  // that isn't one of the standard options (e.g. from a future version)
  // still shows up as a valid, selected item instead of tripping the
  // dropdown's "value must be one of items" assertion.
  late List<int> _maxMessagesItems;

  @override
  void initState() {
    super.initState();
    tempFontSize = widget.initialFontSize;
    tempRetryInterval = widget.initialRetryInterval;
    tempJetStreamEnabled = widget.initialJetStreamEnabled;
    tempKvEnabled = widget.initialKvEnabled;
    tempObjectStoreEnabled = widget.initialObjectStoreEnabled;
    tempServiceDiscoveryEnabled = widget.initialServiceDiscoveryEnabled;
    tempUpdateCheckEnabled = widget.initialUpdateCheckEnabled;
    tempShowSubscriptionColors = widget.initialShowSubscriptionColors;
    tempMaxMessages = widget.initialMaxMessages;
    tempShowTimestamps = widget.initialShowTimestamps;
    _maxMessagesItems = maxMessagesOptions.contains(tempMaxMessages)
        ? maxMessagesOptions
        : [
            ...maxMessagesOptions.where((v) => v != 0 && v < tempMaxMessages),
            tempMaxMessages,
            ...maxMessagesOptions.where((v) => v == 0 || v > tempMaxMessages),
          ];
  }

  String _maxMessagesLabel(int value) {
    if (value == 0) return 'Unlimited';
    if (value >= 1000) return '${value ~/ 1000}k';
    return '$value';
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show Subscription Colors'),
                Switch(
                  value: tempShowSubscriptionColors,
                  onChanged: (v) {
                    setState(() {
                      tempShowSubscriptionColors = v;
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
                const Text('Enable Service Discovery'),
                Switch(
                  value: tempServiceDiscoveryEnabled,
                  onChanged: (v) {
                    setState(() {
                      tempServiceDiscoveryEnabled = v;
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Max Messages Kept'),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: tempMaxMessages,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final value in _maxMessagesItems)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_maxMessagesLabel(value)),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        tempMaxMessages = value!;
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
                const Text('Show Message Timestamps'),
                Switch(
                  value: tempShowTimestamps,
                  onChanged: (v) {
                    setState(() {
                      tempShowTimestamps = v;
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
                tempServiceDiscoveryEnabled,
                tempUpdateCheckEnabled,
                tempShowSubscriptionColors,
                tempMaxMessages,
                tempShowTimestamps);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
