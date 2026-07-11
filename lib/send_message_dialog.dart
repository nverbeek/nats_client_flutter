import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Custom intent for send action
class SendIntent extends Intent {
  const SendIntent();
}

class _HeaderRow {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _HeaderRow({String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class SendMessageDialog extends StatefulWidget {
  final TextEditingController subjectController;
  final TextEditingController dataController;
  final bool jetStreamAvailable;
  final Map<String, String>? initialHeaders;
  final void Function(String subject, String data, bool useJetStream,
      Map<String, String> headers) onSend;

  const SendMessageDialog({
    super.key,
    required this.subjectController,
    required this.dataController,
    this.jetStreamAvailable = false,
    this.initialHeaders,
    required this.onSend,
  });

  @override
  State<SendMessageDialog> createState() => _SendMessageDialogState();
}

class _SendMessageDialogState extends State<SendMessageDialog> {
  bool _useJetStream = false;
  late final List<_HeaderRow> _headerRows;

  @override
  void initState() {
    super.initState();
    _headerRows = widget.initialHeaders == null
        ? []
        : widget.initialHeaders!.entries
            .map((e) => _HeaderRow(key: e.key, value: e.value))
            .toList();
  }

  @override
  void dispose() {
    for (final row in _headerRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addHeaderRow() {
    setState(() => _headerRows.add(_HeaderRow()));
  }

  void _removeHeaderRow(int index) {
    setState(() => _headerRows.removeAt(index).dispose());
  }

  void _send() {
    final headers = <String, String>{};
    for (final row in _headerRows) {
      final key = row.keyController.text.trim();
      if (key.isEmpty) continue;
      headers[key] = row.valueController.text;
    }
    widget.onSend(widget.subjectController.text, widget.dataController.text,
        _useJetStream, headers);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const SendIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter):
            const SendIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SendIntent: CallbackAction<SendIntent>(
            onInvoke: (SendIntent intent) {
              _send();
              return null;
            },
          ),
        },
        child: AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Send Message'),
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
            width: 400, // Optional: set a width for better appearance
            height: widget.jetStreamAvailable ? 500 : 460,
            child: Column(
              children: <Widget>[
                TextFormField(
                  maxLines: 1,
                  controller: widget.subjectController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Subject',
                    labelText: 'Subject',
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TextFormField(
                    controller: widget.dataController,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Data',
                      labelText: 'Data',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Headers', style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addHeaderRow,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 100,
                  child: _headerRows.isEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No headers',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color
                                      ?.withValues(alpha: 0.6),
                                ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _headerRows.length,
                          itemBuilder: (context, index) {
                            final row = _headerRows[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: row.keyController,
                                      maxLines: 1,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        hintText: 'Key',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextFormField(
                                      controller: row.valueController,
                                      maxLines: 1,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        hintText: 'Value',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => _removeHeaderRow(index),
                                    tooltip: 'Remove header',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (widget.jetStreamAvailable)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title:
                        const Text('Publish via JetStream (get delivery ack)'),
                    value: _useJetStream,
                    onChanged: (v) =>
                        setState(() => _useJetStream = v ?? false),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            Tooltip(
              message: 'Hint: Ctrl+Enter (Cmd+Enter on Mac) to send',
              child: TextButton(
                onPressed: _send,
                child: const Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
