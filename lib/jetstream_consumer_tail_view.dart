import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart' as constants;
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

  // Read once at open time -- this view has no constructor-level settings
  // plumbing today, so a change made in Settings while this panel is
  // already open only takes effect the next time it's reopened.
  int _maxMessages = constants.defaultMaxMessages;

  @override
  void initState() {
    super.initState();
    _loadMaxMessages();
    _startTailing();
  }

  Future<void> _loadMaxMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(constants.prefMaxMessages) ??
        constants.defaultMaxMessages;
    if (!mounted) return;
    setState(() => _maxMessages = value);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // dart_nats 1.2.2 (PR #45) fixed the underlying pull-consumer loop that
  // used to swallow delivery errors forever (e.g. after the server-side
  // consumer is deleted out from under it) -- it now surfaces them via this
  // stream's onError, so a separate polling health-probe timer that used to
  // paper over that gap is no longer needed. Cancel on first error so a
  // truly dead consumer doesn't keep retrying/erroring in the background
  // once the row already shows Retry.
  void _startTailing() {
    final consumer =
        widget.manager.tailConsumer(widget.streamName, widget.consumerName);
    _subscription = consumer.messages().listen(
      (message) {
        if (!mounted) return;
        setState(() {
          _messages.insert(0, message);
          if (_maxMessages > 0 && _messages.length > _maxMessages) {
            final dropped = _messages.removeLast();
            _resolved.remove(dropped);
          }
        });
      },
      onError: (Object err) {
        _subscription?.cancel();
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

  // Optimistically mark the row resolved, then wait for the server to
  // actually confirm the ack/nak/term ([ackSync]/[nakSync]/[termSync] --
  // unlike the fire-and-forget [ack]/[nak]/[term], these throw if the
  // publish never reaches the server, e.g. a disconnected client). On
  // failure, revert so the buttons re-enable rather than silently leaving
  // the user believing an unresolved message was handled.
  Future<void> _resolve(Message message, Future<void> Function() action,
      String failureText) async {
    setState(() => _resolved.add(message));
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolved.remove(message));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$failureText ${describeJetStreamError(e)}',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _ack(Message message) => _resolve(
      message, () => message.ackSync(), 'Ack failed — message not acknowledged.');

  void _nak(Message message) => _resolve(
      message, () => message.nakSync(), 'Nak failed — message not redelivered.');

  void _term(Message message) => _resolve(
      message, () => message.termSync(), 'Term failed — message not terminated.');

  Future<void> _showDetailDialog(Message message) async {
    var headerVersion = '';
    Map<String, String> headers = <String, String>{};
    if (message.header != null) {
      headerVersion = message.header?.version ?? '';
      headers = message.header?.headers ?? <String, String>{};
    }

    final text = decodeMessageTextFor(message);
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
              Icon(Icons.circle,
                  size: 10,
                  color: _errorMessage == null
                      ? Colors.green.shade400
                      : Colors.grey.shade500),
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
                    text: decodeMessageTextFor(message),
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
                        onPressed: () => Clipboard.setData(
                            ClipboardData(text: decodeMessageTextFor(message))),
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
