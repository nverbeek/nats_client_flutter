import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:provider/provider.dart';
import 'package:nats_client_flutter/main.dart'; // For ThemeModel
import 'highlight_theme.dart';

class MessageDetailDialog extends StatefulWidget {
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
  State<MessageDetailDialog> createState() => _MessageDetailDialogState();
}

class _MessageDetailDialogState extends State<MessageDetailDialog>
    with SingleTickerProviderStateMixin {
  bool _showCopied = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showCopiedFeedback() {
    setState(() {
      _showCopied = true;
    });
    _animationController.forward().then((_) {
      // Wait for 800ms, then fade out
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _animationController.reverse().then((_) {
            if (mounted) {
              setState(() {
                _showCopied = false;
              });
            }
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    String headerText = '';
    if (widget.headers.isNotEmpty) {
      widget.headers.forEach((k, v) => headerText += '$k: $v\n');
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
            if (widget.headerVersion.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Text(
                  'Header Version',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (widget.headerVersion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: SelectableText(widget.headerVersion),
              ),
            if (widget.headers.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Text(
                  'Headers',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (widget.headers.isNotEmpty)
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
              child: Stack(
                children: [
                  HighlightView(
                    widget.formattedJson,
                    language: 'json',
                    theme: getCustomHighlightTheme(
                      context,
                      isDark: Provider.of<ThemeModel>(context, listen: false).isDark(),
                    ),
                    padding: const EdgeInsets.all(10),
                    textStyle: const TextStyle(
                        fontSize: 14,
                        fontFamily:
                            'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showCopied)
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.green.shade700
                                    : Colors.green.shade600,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Copied!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: widget.formattedJson));
                              _showCopiedFeedback();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.copy,
                                size: 16,
                                color: Theme.of(context).iconTheme.color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
