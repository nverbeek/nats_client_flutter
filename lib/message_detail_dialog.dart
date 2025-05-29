import 'package:flutter/material.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atelier-cave-dark.dart';
import 'package:flutter_highlighter/themes/atelier-cave-light.dart';
import 'package:provider/provider.dart';
import 'package:nats_client_flutter/main.dart'; // For ThemeModel

class MessageDetailDialog extends StatelessWidget {
  final String headerVersion;
  final Map<String, String> headers;
  final String formattedJson;

  const MessageDetailDialog({
    super.key,
    required this.headerVersion,
    required this.headers,
    required this.formattedJson,
  });

  @override
  Widget build(BuildContext context) {
    String headerText = '';
    if (headers.isNotEmpty) {
      headers.forEach((k, v) => headerText += '$k: $v\n');
      headerText = headerText.trim();
    }
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Message Detail'),
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
        child: ListBody(
          children: <Widget>[
            if (headerVersion.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Text(
                  'Header Version',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (headerVersion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: SelectableText(headerVersion),
              ),
            if (headers.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Text(
                  'Headers',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (headers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: SelectableText(headerText),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
              child: Text(
                'Payload',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
              child: HighlightView(
                formattedJson,
                language: 'json',
                theme: Provider.of<ThemeModel>(context, listen: false).isDark()
                    ? atelierCaveDarkTheme
                    : atelierCaveLightTheme,
                padding: const EdgeInsets.all(10),
                textStyle: const TextStyle(
                    fontSize: 14,
                    fontFamily:
                        'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
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
      ],
    );
  }
}
