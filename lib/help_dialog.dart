import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

class HelpDialog extends StatelessWidget {
  final String markdownData;
  const HelpDialog({super.key, required this.markdownData});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: MarkdownBlock(
            data: markdownData,
            config: isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig,
          ),
        ),
      ),
    );
  }
}
