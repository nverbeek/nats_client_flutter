import 'package:flutter/material.dart';

import 'constants.dart' as constants;
import 'pinned_fields_editor.dart';

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

/// Options offered by the "Heartbeat Interval" dropdown, in seconds. 120 is
/// the default (`constants.defaultHeartbeatInterval`).
const List<int> heartbeatIntervalOptions = [15, 30, 60, 120];

/// "30 seconds", "1 minute", "2 minutes".
String formatHeartbeatInterval(int seconds) {
  if (seconds % 60 != 0) return '$seconds seconds';
  final minutes = seconds ~/ 60;
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

/// Why [value] isn't a usable monitoring port, or null if it is.
String? validateMonitorPort(String value) {
  final port = int.tryParse(value.trim());
  if (port == null || port < 1 || port > 65535) {
    return 'Enter a port from 1 to 65535.';
  }
  return null;
}

/// Every value the Settings dialog edits: what it opens with, and what it
/// hands back to `onSave`.
class SettingsValues {
  final double fontSize;
  final int retryInterval;
  final int heartbeatInterval;
  final bool jetStreamEnabled;
  final bool kvEnabled;
  final bool objectStoreEnabled;
  final bool serviceDiscoveryEnabled;
  final bool serverMonitorEnabled;
  final int serverMonitorPort;
  final int serverMonitorInterval;
  final bool updateCheckEnabled;
  final bool showSubscriptionColors;
  final int maxMessages;
  final bool showTimestamps;
  final bool showSubjectChip;
  final int messageMaxLines;
  final List<String> pinnedFields;

  const SettingsValues({
    required this.fontSize,
    required this.retryInterval,
    required this.heartbeatInterval,
    required this.jetStreamEnabled,
    required this.kvEnabled,
    required this.objectStoreEnabled,
    required this.serviceDiscoveryEnabled,
    required this.serverMonitorEnabled,
    required this.serverMonitorPort,
    required this.serverMonitorInterval,
    required this.updateCheckEnabled,
    required this.showSubscriptionColors,
    required this.maxMessages,
    required this.showTimestamps,
    this.showSubjectChip = constants.defaultShowSubjectChip,
    this.messageMaxLines = constants.defaultMessageMaxLines,
    this.pinnedFields = const [],
  });
}

class SettingsDialog extends StatefulWidget {
  final SettingsValues initial;
  final void Function(SettingsValues values) onSave;

  const SettingsDialog({
    super.key,
    required this.initial,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late double tempFontSize;
  late int tempRetryInterval;
  late int tempHeartbeatInterval;
  late bool tempJetStreamEnabled;
  late bool tempKvEnabled;
  late bool tempObjectStoreEnabled;
  late bool tempServiceDiscoveryEnabled;
  late bool tempServerMonitorEnabled;
  late int tempServerMonitorInterval;
  late final TextEditingController _monitorPortController;
  String? _monitorPortError;
  late bool tempUpdateCheckEnabled;
  late bool tempShowSubscriptionColors;
  late int tempMaxMessages;
  late bool tempShowTimestamps;
  late bool tempShowSubjectChip;
  late int tempMessageMaxLines;
  late List<String> tempPinnedFields;
  bool _pinnedInputInvalid = false;
  final GlobalKey<PinnedFieldsEditorState> _pinnedEditorKey = GlobalKey();
  // messageMaxLinesOptions plus, if needed, the persisted value.
  late List<int> _maxLinesItems;
  // maxMessagesOptions plus, if needed, the persisted value -- so a value
  // that isn't one of the standard options (e.g. from a future version)
  // still shows up as a valid, selected item instead of tripping the
  // dropdown's "value must be one of items" assertion.
  late List<int> _maxMessagesItems;
  // heartbeatIntervalOptions plus, if needed, the persisted value (same
  // reasoning as _maxMessagesItems).
  late List<int> _heartbeatItems;
  // serverMonitorIntervalOptions plus, if needed, the persisted value.
  late List<int> _monitorIntervalItems;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    tempFontSize = initial.fontSize;
    tempRetryInterval = initial.retryInterval;
    tempHeartbeatInterval = initial.heartbeatInterval;
    _heartbeatItems = [
      ...heartbeatIntervalOptions,
      if (!heartbeatIntervalOptions.contains(tempHeartbeatInterval))
        tempHeartbeatInterval,
    ]..sort();
    tempJetStreamEnabled = initial.jetStreamEnabled;
    tempKvEnabled = initial.kvEnabled;
    tempObjectStoreEnabled = initial.objectStoreEnabled;
    tempServiceDiscoveryEnabled = initial.serviceDiscoveryEnabled;
    tempServerMonitorEnabled = initial.serverMonitorEnabled;
    tempServerMonitorInterval = initial.serverMonitorInterval;
    _monitorIntervalItems = [
      ...constants.serverMonitorIntervalOptions,
      if (!constants.serverMonitorIntervalOptions
          .contains(tempServerMonitorInterval))
        tempServerMonitorInterval,
    ]..sort();
    _monitorPortController =
        TextEditingController(text: '${initial.serverMonitorPort}');
    tempUpdateCheckEnabled = initial.updateCheckEnabled;
    tempShowSubscriptionColors = initial.showSubscriptionColors;
    tempMaxMessages = initial.maxMessages;
    tempShowTimestamps = initial.showTimestamps;
    tempShowSubjectChip = initial.showSubjectChip;
    tempMessageMaxLines = initial.messageMaxLines;
    tempPinnedFields = List.of(initial.pinnedFields);
    _maxLinesItems = [
      ...constants.messageMaxLinesOptions,
      if (!constants.messageMaxLinesOptions.contains(tempMessageMaxLines))
        tempMessageMaxLines,
    ]..sort();
    _maxMessagesItems = maxMessagesOptions.contains(tempMaxMessages)
        ? maxMessagesOptions
        : [
            ...maxMessagesOptions.where((v) => v != 0 && v < tempMaxMessages),
            tempMaxMessages,
            ...maxMessagesOptions.where((v) => v == 0 || v > tempMaxMessages),
          ];
  }

  @override
  void dispose() {
    _monitorPortController.dispose();
    super.dispose();
  }

  // A bad port only blocks Save while monitoring is on; with it off the
  // field is hidden and the saved port is left as it was.
  bool get _canSave =>
      (!tempServerMonitorEnabled || _monitorPortError == null) &&
      !_pinnedInputInvalid;

  String _maxMessagesLabel(int value) {
    if (value == 0) return 'Unlimited';
    if (value >= 1000) return '${value ~/ 1000}k';
    return '$value';
  }

  // Two columns once the dialog has this much room; one below it.
  static const double _twoColumnMinWidth = 760;
  static const double _maxDialogWidth = 920;
  static const double _controlWidth = 200;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    // AlertDialog's own inset is 40px a side; keep inside it.
    final dialogWidth = (screenWidth - 80).clamp(320.0, _maxDialogWidth);
    final twoColumns = dialogWidth >= _twoColumnMinWidth;

    final messages = _section(context, 'Messages', [
      _fontSizeRow(),
      _dropdownRow<int>(
        key: const ValueKey('messageMaxLinesField'),
        label: 'Max Lines per Message',
        tooltip: 'Long messages wrap up to this many lines. 1 keeps every '
            'message on a single line.',
        value: tempMessageMaxLines,
        items: {
          for (final lines in _maxLinesItems)
            lines: lines == 1 ? '1 line' : '$lines lines',
        },
        onChanged: (v) => tempMessageMaxLines = v,
      ),
      _dropdownRow<int>(
        label: 'Max Messages Kept',
        tooltip: 'Once the cap is reached, the oldest messages are dropped.',
        value: tempMaxMessages,
        items: {for (final v in _maxMessagesItems) v: _maxMessagesLabel(v)},
        onChanged: (v) => tempMaxMessages = v,
      ),
      _switchRow(
        key: const ValueKey('showSubjectChipSwitch'),
        label: 'Show Message Subjects',
        tooltip: "When off, the subject is still in Message Detail and the "
            "row menu's Copy Subject.",
        value: tempShowSubjectChip,
        onChanged: (v) => tempShowSubjectChip = v,
      ),
      _switchRow(
        key: const ValueKey('showTimestampsSwitch'),
        label: 'Show Message Timestamps',
        value: tempShowTimestamps,
        onChanged: (v) => tempShowTimestamps = v,
      ),
      _switchRow(
        key: const ValueKey('showSubscriptionColorsSwitch'),
        label: 'Show Subscription Colors',
        value: tempShowSubscriptionColors,
        onChanged: (v) => tempShowSubscriptionColors = v,
      ),
    ]);

    final connection = _section(context, 'Connection', [
      _dropdownRow<int>(
        label: 'Reconnect Interval',
        value: tempRetryInterval,
        items: const {
          3: '3 seconds',
          5: '5 seconds',
          10: '10 seconds',
          30: '30 seconds',
        },
        onChanged: (v) => tempRetryInterval = v,
      ),
      _dropdownRow<int>(
        label: 'Heartbeat Interval',
        tooltip: 'How often to check that the connection is alive. A dead '
            'connection is detected after about two missed checks. Applies '
            'on the next connect.',
        value: tempHeartbeatInterval,
        items: {
          for (final s in _heartbeatItems) s: formatHeartbeatInterval(s),
        },
        onChanged: (v) => tempHeartbeatInterval = v,
      ),
    ]);

    final tabs = _section(context, 'Tabs & Server', [
      _switchRow(
        key: const ValueKey('jetStreamSwitch'),
        label: 'Enable JetStream',
        value: tempJetStreamEnabled,
        onChanged: (v) => tempJetStreamEnabled = v,
      ),
      _switchRow(
        key: const ValueKey('kvSwitch'),
        label: 'Enable Key-Value Stores',
        value: tempKvEnabled,
        onChanged: (v) => tempKvEnabled = v,
      ),
      _switchRow(
        key: const ValueKey('objectStoreSwitch'),
        label: 'Enable Object Store',
        value: tempObjectStoreEnabled,
        onChanged: (v) => tempObjectStoreEnabled = v,
      ),
      _switchRow(
        key: const ValueKey('serviceDiscoverySwitch'),
        label: 'Enable Service Discovery',
        value: tempServiceDiscoveryEnabled,
        onChanged: (v) => tempServiceDiscoveryEnabled = v,
      ),
      _switchRow(
        key: const ValueKey('serverMonitorSwitch'),
        label: 'Enable Server Monitoring',
        tooltip: "Shows a Server tab that polls the server's HTTP monitoring "
            'port (/varz, /connz). That port has no authentication and is '
            'off unless the server was started with -m or http_port.',
        value: tempServerMonitorEnabled,
        onChanged: (v) => tempServerMonitorEnabled = v,
      ),
      if (tempServerMonitorEnabled) _monitorRow(),
    ]);

    final updates = _section(context, 'Updates', [
      _switchRow(
        key: const ValueKey('updateCheckSwitch'),
        label: 'Check for Updates',
        value: tempUpdateCheckEnabled,
        onChanged: (v) => tempUpdateCheckEnabled = v,
      ),
    ]);

    final pinned = _section(context, 'Pinned Fields', [
      PinnedFieldsEditor(
        key: _pinnedEditorKey,
        initial: tempPinnedFields,
        onChanged: (pins) => tempPinnedFields = pins,
        onPendingErrorChanged: (invalid) =>
            setState(() => _pinnedInputInvalid = invalid),
      ),
    ]);

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
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (twoColumns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: messages),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [connection, tabs, updates],
                      ),
                    ),
                  ],
                )
              else ...[
                messages,
                connection,
                tabs,
                updates,
              ],
              pinned,
            ],
          ),
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
          onPressed: !_canSave
              ? null
              : () {
                  // A path typed but not yet added with Enter still counts.
                  if (!(_pinnedEditorKey.currentState?.commitPending() ??
                      true)) {
                    return;
                  }
                  widget.onSave(SettingsValues(
                    fontSize: tempFontSize,
                    retryInterval: tempRetryInterval,
                    heartbeatInterval: tempHeartbeatInterval,
                    jetStreamEnabled: tempJetStreamEnabled,
                    kvEnabled: tempKvEnabled,
                    objectStoreEnabled: tempObjectStoreEnabled,
                    serviceDiscoveryEnabled: tempServiceDiscoveryEnabled,
                    serverMonitorEnabled: tempServerMonitorEnabled,
                    serverMonitorPort:
                        validateMonitorPort(_monitorPortController.text) == null
                            ? int.parse(_monitorPortController.text.trim())
                            : widget.initial.serverMonitorPort,
                    serverMonitorInterval: tempServerMonitorInterval,
                    updateCheckEnabled: tempUpdateCheckEnabled,
                    showSubscriptionColors: tempShowSubscriptionColors,
                    maxMessages: tempMaxMessages,
                    showTimestamps: tempShowTimestamps,
                    showSubjectChip: tempShowSubjectChip,
                    messageMaxLines: tempMessageMaxLines,
                    pinnedFields: tempPinnedFields,
                  ));
                  Navigator.of(context).pop();
                },
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// A titled group of settings rows.
  Widget _section(BuildContext context, String title, List<Widget> rows) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: row,
            ),
        ],
      ),
    );
  }

  Widget _label(String label, String? tooltip) {
    final text = Text(label);
    return tooltip == null ? text : Tooltip(message: tooltip, child: text);
  }

  Widget _switchRow({
    required Key key,
    required String label,
    String? tooltip,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: _label(label, tooltip)),
          Switch(
            key: key,
            value: value,
            onChanged: (v) => setState(() => onChanged(v)),
          ),
        ],
      ),
    );
  }

  Widget _dropdownRow<T>({
    Key? key,
    required String label,
    String? tooltip,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: _label(label, tooltip)),
        SizedBox(
          width: _controlWidth,
          child: DropdownButtonFormField<T>(
            key: key,
            initialValue: value,
            isDense: true,
            // Long labels ellipsize instead of overflowing the fixed width.
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              for (final entry in items.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => onChanged(v));
            },
          ),
        ),
      ],
    );
  }

  Widget _fontSizeRow() {
    return Row(
      children: [
        const Expanded(child: Text('Message Font Size')),
        SizedBox(
          width: _controlWidth,
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  min: 10,
                  max: 30,
                  divisions: 20,
                  value: tempFontSize,
                  label: tempFontSize.round().toString(),
                  onChanged: (v) => setState(() => tempFontSize = v),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(tempFontSize.round().toString(),
                    textAlign: TextAlign.end),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Monitoring port and poll interval, shown under the Server Monitoring
  /// switch while it's on.
  Widget _monitorRow() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('monitorPortField'),
              controller: _monitorPortController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monitoring Port',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: _monitorPortError,
              ),
              onChanged: (v) {
                setState(() {
                  _monitorPortError = validateMonitorPort(v);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: const ValueKey('monitorIntervalField'),
              initialValue: tempServerMonitorInterval,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Poll Every',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final seconds in _monitorIntervalItems)
                  DropdownMenuItem(
                      value: seconds,
                      child:
                          Text(seconds == 1 ? '1 second' : '$seconds seconds')),
              ],
              onChanged: (value) {
                setState(() {
                  tempServerMonitorInterval = value!;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
