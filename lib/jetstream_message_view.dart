import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jetstream_manager.dart';
import 'message_detail_dialog.dart';
import 'regex_text_highlight.dart';

/// Live "Browse Messages" panel for a single JetStream stream.
///
/// Uses an ephemeral, auto-cleaning [OrderedConsumer] under the hood so the
/// user never has to think about consumer setup just to look at what's in a
/// stream — opening this panel starts the tail, closing it (or disposing)
/// tears the consumer down again. Mirrors the look and feel of the Live
/// Messages list in `main.dart` for visual consistency.
class JetStreamMessageView extends StatefulWidget {
  final String streamName;
  final JetStreamManager manager;
  final VoidCallback onClose;

  const JetStreamMessageView({
    super.key,
    required this.streamName,
    required this.manager,
    required this.onClose,
  });

  @override
  State<JetStreamMessageView> createState() => JetStreamMessageViewState();
}

class JetStreamMessageViewState extends State<JetStreamMessageView> {
  OrderedConsumer? _consumer;
  StreamSubscription<Message>? _subscription;
  final List<Message> _messages = [];
  List<Message> _filteredMessages = [];
  String? _errorMessage;

  String _currentFilter = '';
  String _currentFind = '';
  final _filterController = TextEditingController();
  final _findController = TextEditingController();
  final _filterFocusNode = FocusNode();
  final _findFocusNode = FocusNode();

  /// Lets the app-wide Ctrl+F / Ctrl+Shift+F shortcut handler in `main.dart`
  /// reach this view's Find field via the `GlobalKey` held by
  /// `JetStreamDashboard` when this view is the one currently showing.
  void focusFindField() => _findFocusNode.requestFocus();

  /// See [focusFindField].
  void focusFilterField() => _filterFocusNode.requestFocus();

  @override
  void initState() {
    super.initState();
    _startBrowsing();
  }

  @override
  void didUpdateWidget(covariant JetStreamMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamName != widget.streamName) {
      _stopBrowsing();
      _messages.clear();
      _filteredMessages = [];
      _errorMessage = null;
      _startBrowsing();
    }
  }

  @override
  void dispose() {
    _stopBrowsing();
    _filterController.dispose();
    _findController.dispose();
    _filterFocusNode.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  void _startBrowsing() {
    final consumer = widget.manager.browseStream(widget.streamName);
    _consumer = consumer;
    _subscription = consumer.messages().listen(
      (message) {
        if (!mounted) return;
        setState(() {
          _messages.insert(0, message);
          _runFilter();
        });
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = describeJetStreamError(err);
        });
      },
    );
  }

  void _stopBrowsing() {
    _subscription?.cancel();
    _subscription = null;
    _consumer?.stop();
    _consumer = null;
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _messages.clear();
      _filteredMessages = [];
    });
    _stopBrowsing();
    _startBrowsing();
  }

  void _runFilter() {
    if (_currentFilter.isEmpty) {
      _filteredMessages = _messages;
    } else {
      _filteredMessages = _messages
          .where((message) =>
              message.string.toLowerCase().contains(_currentFilter.toLowerCase()))
          .toList();
    }
  }

  Future<void> _showDetailDialog(Message message) async {
    var headerVersion = '';
    Map<String, String> headers = <String, String>{};
    if (message.header != null) {
      headerVersion = message.header?.version ?? '';
      headers = message.header?.headers ?? <String, String>{};
    }

    String formattedJson;
    try {
      final json = jsonDecode(message.string);
      final encoder = const JsonEncoder.withIndent('    ');
      formattedJson = encoder.convert(json);
    } on FormatException {
      formattedJson = message.string;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => MessageDetailDialog(
        headerVersion: headerVersion,
        headers: headers,
        formattedJson: formattedJson,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rowEvenColor = isDark
        ? Color.alphaBlend(
            theme.colorScheme.surface.withAlpha(40), theme.colorScheme.surface)
        : Color.alphaBlend(
            theme.colorScheme.surface.withAlpha(20), theme.colorScheme.surface);
    final rowOddColor = isDark
        ? Color.alphaBlend(theme.colorScheme.secondaryContainer.withAlpha(80),
            theme.colorScheme.surface)
        : Color.alphaBlend(theme.colorScheme.secondaryContainer.withAlpha(140),
            theme.colorScheme.surface);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to stream details',
                onPressed: widget.onClose,
              ),
              Icon(Icons.circle, size: 10, color: Colors.green.shade400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Browsing: ${widget.streamName}',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_currentFilter.isEmpty
                  ? '${_messages.length} received'
                  : '${_filteredMessages.length} / ${_messages.length} shown'),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _filterController,
                  focusNode: _filterFocusNode,
                  onChanged: (value) {
                    setState(() {
                      _currentFilter = value;
                      _runFilter();
                    });
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Filter',
                    labelText: 'Filter',
                    prefixIcon: const Icon(Icons.filter_list),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _filterController.clear();
                          _currentFilter = '';
                          _runFilter();
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _findController,
                  focusNode: _findFocusNode,
                  onChanged: (value) {
                    setState(() {
                      _currentFind = value;
                    });
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Find',
                    labelText: 'Find',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _findController.clear();
                          _currentFind = '';
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!)),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          )
        else if (_messages.isEmpty)
          const Expanded(
            child: Center(child: Text('Waiting for messages...')),
          )
        else if (_filteredMessages.isEmpty)
          const Expanded(
            child: Center(child: Text('No messages match filter.')),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _filteredMessages.length,
              itemBuilder: (context, index) {
                final message = _filteredMessages[index];
                final seq = message.streamSequence;
                return Material(
                  key: ValueKey(message.hashCode),
                  child: ListTile(
                    tileColor: index % 2 == 0 ? rowEvenColor : rowOddColor,
                    title: RegexTextHighlight(
                      text: message.string,
                      searchTerm: _currentFind,
                      fontSize: 14,
                      highlightStyle: TextStyle(
                        background: Paint()
                          ..color = theme.colorScheme.inversePrimary,
                        fontSize: 14,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _showDetailDialog(message),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (seq != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 5, 0),
                            child: Chip(label: Text('#$seq')),
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Tooltip(
                            message: message.subject ?? '',
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 5, 0),
                              child: Chip(
                                label: Text(
                                  message.subject ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'copy', child: Text('Copy')),
                            PopupMenuItem(
                                value: 'detail', child: Text('Detail')),
                          ],
                          onSelected: (value) {
                            switch (value) {
                              case 'copy':
                                Clipboard.setData(
                                    ClipboardData(text: message.string));
                                break;
                              case 'detail':
                                _showDetailDialog(message);
                                break;
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
