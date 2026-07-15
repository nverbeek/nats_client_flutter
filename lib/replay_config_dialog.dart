import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'format_utils.dart';
import 'message_export.dart';

/// Real, `file_picker`-backed implementation of "pick a local NDJSON file to
/// replay" -- the default used outside of tests, mirroring
/// `object_store_dashboard.dart`'s `_defaultPickUploadFile` exactly.
Future<(Uint8List, String)?> _defaultPickReplayFile() async {
  final result = await FilePicker.platform.pickFiles(
    withData: true,
    allowedExtensions: ['ndjson', 'jsonl'],
    type: FileType.custom,
  );
  if (result == null) return null;
  final file = result.files.first;

  Uint8List? bytes = file.bytes;
  if (bytes == null && !kIsWeb && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null) return null;
  return (bytes, file.name);
}

/// Config dialog for Replay: pick a previously-exported NDJSON file, set
/// the three pacing knobs, see a live "will send N messages over ~M"
/// preview, then confirm to hand everything back to the caller via
/// [onReplay]. The actual publish loop (and its progress, via
/// `ReplayBanner`) lives in the caller, not this dialog -- mirrors how
/// `CreateStreamDialog.onCreate` hands work back rather than doing it
/// itself.
class ReplayConfigDialog extends StatefulWidget {
  final bool isConnected;
  final void Function(List<ExportedMessage> messages, Duration messageInterval,
      int repeatCount, Duration repeatInterval) onReplay;
  final Future<(Uint8List, String)?> Function() pickFile;

  const ReplayConfigDialog({
    super.key,
    required this.isConnected,
    required this.onReplay,
    Future<(Uint8List, String)?> Function()? pickFile,
  }) : pickFile = pickFile ?? _defaultPickReplayFile;

  @override
  State<ReplayConfigDialog> createState() => _ReplayConfigDialogState();
}

class _ReplayConfigDialogState extends State<ReplayConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageIntervalController = TextEditingController(text: '0');
  final _repeatCountController = TextEditingController(text: '0');
  final _repeatIntervalController = TextEditingController(text: '0');

  String? _fileName;
  List<ExportedMessage>? _parsedMessages;
  int _parseErrorCount = 0;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _messageIntervalController.addListener(_onFieldChanged);
    _repeatCountController.addListener(_onFieldChanged);
    _repeatIntervalController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _messageIntervalController.dispose();
    _repeatCountController.dispose();
    _repeatIntervalController.dispose();
    super.dispose();
  }

  static int? _nonNegativeInt(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || value < 0) return null;
    return value;
  }

  int? get _messageIntervalMs =>
      _nonNegativeInt(_messageIntervalController.text);
  int? get _repeatCount => _nonNegativeInt(_repeatCountController.text);
  int? get _repeatIntervalMs =>
      _nonNegativeInt(_repeatIntervalController.text);

  Future<void> _chooseFile() async {
    setState(() => _picking = true);
    try {
      final picked = await widget.pickFile();
      if (picked == null) return;
      final (bytes, name) = picked;
      final content = utf8.decode(bytes, allowMalformed: true);
      final result = parseExportedMessagesNdjson(content);
      if (!mounted) return;
      setState(() {
        _fileName = name;
        _parsedMessages = result.messages;
        _parseErrorCount = result.errors.length;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool get _canStart =>
      widget.isConnected &&
      (_parsedMessages?.isNotEmpty ?? false) &&
      _messageIntervalMs != null &&
      _repeatCount != null &&
      _repeatIntervalMs != null;

  void _submit() {
    if (!_canStart) return;
    if (!_formKey.currentState!.validate()) return;

    widget.onReplay(
      _parsedMessages!,
      Duration(milliseconds: _messageIntervalMs!),
      _repeatCount!,
      Duration(milliseconds: _repeatIntervalMs!),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _parsedMessages;
    final fileCount = messages?.length ?? 0;
    final messageIntervalMs = _messageIntervalMs ?? 0;
    final repeatCount = _repeatCount ?? 0;
    final repeatIntervalMs = _repeatIntervalMs ?? 0;
    final totalPasses = repeatCount + 1;
    final totalMessages = fileCount * totalPasses;
    final estimatedMs = fileCount > 0
        ? messageIntervalMs * (fileCount - 1) * totalPasses +
            repeatIntervalMs * repeatCount
        : 0;

    return AlertDialog(
      // Content is a fixed-width Form with several fields plus a live
      // preview -- taller than some viewports (e.g. the default test
      // surface), so it needs to scroll rather than overflow.
      scrollable: true,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Replay Messages'),
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
              if (!widget.isConnected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Connect to a server to enable Replay.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fileName ?? 'No file chosen',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _picking ? null : _chooseFile,
                    child: const Text('Choose File'),
                  ),
                ],
              ),
              if (messages != null)
                Text('$fileCount message(s) parsed.',
                    style: Theme.of(context).textTheme.bodySmall),
              if (_parseErrorCount > 0)
                Text(
                  '$_parseErrorCount line(s) could not be parsed and will be skipped.',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Message Interval (ms)',
                ),
                validator: (v) => _nonNegativeInt(v ?? '') == null
                    ? 'Enter a non-negative whole number.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeatCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Repeat Count',
                  helperText: '0 = play once, no repeat',
                ),
                validator: (v) => _nonNegativeInt(v ?? '') == null
                    ? 'Enter a non-negative whole number.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeatIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Repeat Interval (ms)',
                ),
                validator: (v) => _nonNegativeInt(v ?? '') == null
                    ? 'Enter a non-negative whole number.'
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                fileCount > 0
                    ? 'Will send ${formatGroupedCount(totalMessages)} messages over '
                        '${formatEstimatedDuration(Duration(milliseconds: estimatedMs))}'
                    : 'Choose a file to see a preview.',
                style: Theme.of(context).textTheme.bodyMedium,
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
          onPressed: _canStart ? _submit : null,
          child: const Text('Start Replay'),
        ),
      ],
    );
  }
}
