import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

class HelpDialog extends StatelessWidget {
  final String markdownData;
  const HelpDialog({super.key, required this.markdownData});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: MarkdownBlock(
                data: markdownData,
                config: isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }
}
