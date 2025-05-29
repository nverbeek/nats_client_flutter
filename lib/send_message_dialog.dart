import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Custom intent for send action
class SendIntent extends Intent {
  const SendIntent();
}

class SendMessageDialog extends StatelessWidget {
  final TextEditingController subjectController;
  final TextEditingController dataController;
  final void Function(String, String) onSend;

  const SendMessageDialog({
    super.key,
    required this.subjectController,
    required this.dataController,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter): const SendIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SendIntent: CallbackAction<SendIntent>(
            onInvoke: (SendIntent intent) {
              onSend(subjectController.text, dataController.text);
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
            height: 300, // Set a fixed height for the dialog
            child: Column(
              children: <Widget>[
                TextFormField(
                  maxLines: 1,
                  controller: subjectController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Subject',
                    labelText: 'Subject',
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TextFormField(
                    controller: dataController,
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
              message: 'Hint: Ctrl+Enter to send',
              child: TextButton(
                child: const Text('Send'),
                onPressed: () {
                  onSend(subjectController.text, dataController.text);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
