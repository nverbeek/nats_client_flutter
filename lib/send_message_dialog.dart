import 'package:flutter/material.dart';

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
    return AlertDialog(
      title: const Text('Send Message'),
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
    );
  }
}
