import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format_utils.dart';
import 'jetstream_manager.dart';
import 'message_detail_dialog.dart';
import 'regex_text_highlight.dart';

/// Live tail of a specific, user-created consumer — unlike
/// [JetStreamMessageView]'s ephemeral ordered-consumer browse, this binds to
/// a named consumer and honors whatever ack policy it was created with, so
/// explicit-ack consumers can actually be acked/nak'd/terminated here.
class JetStreamConsumerTailView extends StatefulWidget {
  final String streamName;
  final String consumerName;
  final bool explicitAck;
  final JetStreamManager manager;
  final VoidCallback onClose;

  const JetStreamConsumerTailView({
    super.key,
    required this.streamName,
    required this.consumerName,
    required this.explicitAck,
    required this.manager,
    required this.onClose,
  });

  @override
  State<JetStreamConsumerTailView> createState() =>
      _JetStreamConsumerTailViewState();
}

class _JetStreamConsumerTailViewState extends State<JetStreamConsumerTailView> {
  StreamSubscription<Message>? _subscription;
  final List<Message> _messages = [];
  final Set<Message> _resolved = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startTailing();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startTailing() {
    final consumer =
        widget.manager.tailConsumer(widget.streamName, widget.consumerName);
    _subscription = consumer.messages().listen(
      (message) {
        if (!mounted) return;
        setState(() {
          _messages.insert(0, message);
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

  void _retry() {
    setState(() {
      _errorMessage = null;
      _messages.clear();
      _resolved.clear();
    });
    _subscription?.cancel();
    _startTailing();
  }

  void _ack(Message message) {
    message.ack();
    setState(() => _resolved.add(message));
  }

  void _nak(Message message) {
    message.nak();
    setState(() => _resolved.add(message));
  }

  void _term(Message message) {
    message.term();
    setState(() => _resolved.add(message));
  }

  Future<void> _showDetailDialog(Message message) async {
    var headerVersion = '';
    Map<String, String> headers = <String, String>{};
    if (message.header != null) {
      headerVersion = message.header?.version ?? '';
      headers = message.header?.headers ?? <String, String>{};
    }

    final text = decodeMessageText(message.byte);
    String formattedJson;
    try {
      final json = jsonDecode(text);
      final encoder = const JsonEncoder.withIndent('    ');
      formattedJson = encoder.convert(json);
    } on FormatException {
      formattedJson = text;
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
                  'Tailing consumer: ${widget.consumerName}',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_messages.length} received'),
            ],
          ),
        ),
        const Divider(height: 1),
        if (!widget.explicitAck)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              'This consumer\'s ack policy is not "explicit" — Ack/Nak/Term '
              'buttons are disabled because the server does not expect acks.',
              style: theme.textTheme.bodySmall,
            ),
          ),
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
        else
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final resolved = _resolved.contains(message);
                return ListTile(
                  key: ValueKey(message.hashCode),
                  title: RegexTextHighlight(
                    text: decodeMessageText(message.byte),
                    searchTerm: '',
                    fontSize: 14,
                    highlightStyle: TextStyle(
                      background: Paint()
                        ..color = theme.colorScheme.inversePrimary,
                      fontSize: 14,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(message.subject ?? ''),
                  onTap: () => _showDetailDialog(message),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        tooltip: 'Ack',
                        color: Colors.green,
                        onPressed: widget.explicitAck && !resolved
                            ? () => _ack(message)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay),
                        tooltip: 'Nak (redeliver)',
                        color: Colors.orange,
                        onPressed: widget.explicitAck && !resolved
                            ? () => _nak(message)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.block),
                        tooltip: 'Term (stop redelivery)',
                        color: Colors.red,
                        onPressed: widget.explicitAck && !resolved
                            ? () => _term(message)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy',
                        onPressed: () => Clipboard.setData(ClipboardData(
                            text: decodeMessageText(message.byte))),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
