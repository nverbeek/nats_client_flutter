import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:provider/provider.dart';
import 'package:nats_client_flutter/main.dart'; // For ThemeModel
import 'format_utils.dart';
import 'highlight_theme.dart';

class MessageDetailDialog extends StatefulWidget {
  final String headerVersion;
  final Map<String, String> headers;
  final String formattedJson;
  // Arrival time, if known -- `null` for a message with no captured arrival
  // time (e.g. the JetStream Browse/Tail views, which don't tag one). The
  // Live Messages Settings toggle governs only the thin per-row timestamp;
  // this row is shown here whenever the data is available, regardless of
  // that toggle.
  final DateTime? capturedAt;
  // Raw payload bytes, if available -- `null` for the handful of existing
  // call sites/tests that only ever had [formattedJson]. When present, the
  // Payload section gains a Text/Hex toggle, defaulting to Hex whenever the
  // payload isn't valid UTF-8 (e.g. protobuf, compressed data).
  final Uint8List? payloadBytes;

  const MessageDetailDialog({
    super.key,
    required this.headerVersion,
    required this.headers,
    required this.formattedJson,
    this.capturedAt,
    this.payloadBytes,
  });

  @override
  State<MessageDetailDialog> createState() => _MessageDetailDialogState();
}

enum _CopiedSection { headers, payload }

class _MessageDetailDialogState extends State<MessageDetailDialog>
    with SingleTickerProviderStateMixin {
  _CopiedSection? _copiedSection;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late bool _showHex;

  // Computed lazily (only if the Hex view is actually opened) and only once
  // per dialog, since `payloadBytes` never changes for the lifetime of this
  // dialog instance.
  late final String _hexDump =
      widget.payloadBytes != null ? formatHexDump(widget.payloadBytes!) : '';

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
    // Auto-detect: default to the Hex view whenever the payload isn't valid
    // UTF-8 (protobuf, compressed data, etc). Always a manual toggle either
    // way once the dialog is open.
    _showHex = widget.payloadBytes != null &&
        !isValidUtf8(widget.payloadBytes!);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showCopiedFeedback(_CopiedSection section) {
    setState(() {
      _copiedSection = section;
    });
    _animationController.forward().then((_) {
      // Wait for 800ms, then fade out
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _animationController.reverse().then((_) {
            if (mounted) {
              setState(() {
                _copiedSection = null;
              });
            }
          });
        }
      });
    });
  }

  Widget _copiedBadge() {
    return FadeTransition(
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
              color: Colors.black.withValues(alpha: 0.2),
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
    );
  }

  Widget _copyButton({required VoidCallback onTap, double iconPadding = 8}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(iconPadding),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
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
    );
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
            if (widget.capturedAt != null) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Text(
                  'Received',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: SelectableText(
                    formatFullTimestamp(widget.capturedAt!)),
              ),
            ],
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
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Headers',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_copiedSection == _CopiedSection.headers)
                          _copiedBadge(),
                        _copyButton(
                          iconPadding: 6,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: headerText));
                            _showCopiedFeedback(_CopiedSection.headers);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (widget.headers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                      1: IntrinsicColumnWidth(flex: 1),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    children: [
                      for (final entry in widget.headers.entries)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: SelectableText(
                                entry.key,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: SelectableText(entry.value),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.formattedJson.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Payload',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (widget.payloadBytes != null)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Text'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Hex'),
                          ),
                        ],
                        selected: {_showHex},
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (selection) =>
                            setState(() => _showHex = selection.first),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: _showHex
                          ? Container(
                              key: const Key('hexPayloadBackground'),
                              width: double.infinity,
                              color: Theme.of(context).colorScheme.surface,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: SelectableText(
                                    _hexDump,
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color,
                                        fontFamily:
                                            'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
                                  ),
                                ),
                              ),
                            )
                          : HighlightView(
                              widget.formattedJson,
                              language: 'json',
                              theme: getCustomHighlightTheme(
                                context,
                                isDark: Provider.of<ThemeModel>(context,
                                        listen: false)
                                    .isDark(),
                              ),
                              padding: const EdgeInsets.all(10),
                              textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontFamily:
                                      'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_copiedSection == _CopiedSection.payload)
                            _copiedBadge(),
                          _copyButton(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                  text:
                                      _showHex ? _hexDump : widget.formattedJson));
                              _showCopiedFeedback(_CopiedSection.payload);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Text(
                  'Payload',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This message has no payload',
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
