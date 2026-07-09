import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Custom intent for send action
class SendIntent extends Intent {
  const SendIntent();
}

class SendMessageDialog extends StatefulWidget {
  final TextEditingController subjectController;
  final TextEditingController dataController;
  final bool jetStreamAvailable;
  final void Function(String subject, String data, bool useJetStream) onSend;

  const SendMessageDialog({
    super.key,
    required this.subjectController,
    required this.dataController,
    this.jetStreamAvailable = false,
    required this.onSend,
  });

  @override
  State<SendMessageDialog> createState() => _SendMessageDialogState();
}

class _SendMessageDialogState extends State<SendMessageDialog> {
  bool _useJetStream = false;

  void _send() {
    widget.onSend(widget.subjectController.text, widget.dataController.text,
        _useJetStream);
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
            height: widget.jetStreamAvailable ? 340 : 300,
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
