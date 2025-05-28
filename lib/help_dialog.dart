import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class HelpDialog extends StatelessWidget {
  final String markdownData;
  const HelpDialog({super.key, required this.markdownData});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: ListBody(
            children: [
              MarkdownBody(
                data: markdownData,
                shrinkWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
