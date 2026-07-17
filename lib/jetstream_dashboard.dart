import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'account_info_dialog.dart';
import 'jetstream_consumer_dialog.dart';
import 'jetstream_consumer_tail_view.dart';
import 'jetstream_manager.dart';
import 'jetstream_message_view.dart';
import 'jetstream_stream_dialog.dart';

/// JetStream tab content: a monitor and management dashboard for streams and
/// consumers, plus a live "Browse Messages" tail for a selected stream.
///
/// Takes an already-constructed [JetStreamManager] (rather than a raw
/// `Client`) so tests can inject a fake manager and exercise the connected
/// dashboard states without a live NATS server.
class JetStreamDashboard extends StatefulWidget {
  /// The active JetStream manager, or `null` when not currently connected.
  final JetStreamManager? manager;

  const JetStreamDashboard({super.key, required this.manager});

  @override
  State<JetStreamDashboard> createState() => JetStreamDashboardState();
}

class JetStreamDashboardState extends State<JetStreamDashboard> {
  bool _checkingAvailability = false;
  String? _availabilityError;

  bool _loadingStreams = false;
  String? _streamsError;
  List<StreamInfo> _streams = [];

  String? _selectedStreamName;
  bool _loadingConsumers = false;
  String? _consumersError;
  List<ConsumerInfo> _consumers = [];

  bool _browsing = false;
  String? _tailingConsumerName;
  bool _tailingConsumerExplicitAck = false;

  bool _mutating = false;

  /// Lets the app-wide Ctrl+F / Ctrl+Shift+F shortcut handler in `main.dart`
  /// reach the Browse Messages view's Filter/Find fields when it's the one
  /// currently showing, via the `GlobalKey` `main.dart` holds on this state.
  final GlobalKey<JetStreamMessageViewState> _browseViewKey = GlobalKey();

  /// Returns whether the Browse Messages view is currently showing (and, if
  /// so, focuses its Find field).
  bool focusFindField() {
    final state = _browseViewKey.currentState;
    if (state == null) return false;
    state.focusFindField();
    return true;
  }

  /// See [focusFindField].
  bool focusFilterField() {
    final state = _browseViewKey.currentState;
    if (state == null) return false;
    state.focusFilterField();
    return true;
  }

  @override
  void initState() {
    super.initState();
    if (widget.manager != null) {
      _checkAvailability();
    }
  }

  @override
  void didUpdateWidget(covariant JetStreamDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager == widget.manager) return;

    if (widget.manager == null) {
      // Disconnected: drop all cached state so a future reconnect starts fresh.
      setState(() {
        _checkingAvailability = false;
        _availabilityError = null;
        _streamsError = null;
        _streams = [];
        _consumers = [];
        _selectedStreamName = null;
        _browsing = false;
        _tailingConsumerName = null;
        _mutating = false;
      });
      return;
    }

    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _checkingAvailability = true;
      _availabilityError = null;
    });

    final error = await manager.checkAvailability();
    if (!mounted || widget.manager != manager) return;

    setState(() {
      _checkingAvailability = false;
      _availabilityError = error;
    });

    if (error == null) {
      _loadStreams();
    }
  }

  Future<void> _loadStreams() async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _loadingStreams = true;
      _streamsError = null;
    });

    try {
      final streams = await manager.listStreams();
      if (!mounted || widget.manager != manager) return;
      setState(() {
        _streams = streams;
        _loadingStreams = false;
      });
    } catch (e) {
      if (!mounted || widget.manager != manager) return;
      setState(() {
        _streamsError = describeJetStreamError(e);
        _loadingStreams = false;
      });
    }
  }

  Future<void> _selectStream(String streamName) async {
    setState(() {
      _selectedStreamName = streamName;
      _browsing = false;
      _tailingConsumerName = null;
      _consumers = [];
      _consumersError = null;
    });
    await _loadConsumers(streamName);
  }

  Future<void> _loadConsumers(String streamName) async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _loadingConsumers = true;
      _consumersError = null;
    });

    try {
      final consumers = await manager.listConsumers(streamName);
      if (!mounted ||
          widget.manager != manager ||
          _selectedStreamName != streamName) {
        return;
      }
      setState(() {
        _consumers = consumers;
        _loadingConsumers = false;
      });
    } catch (e) {
      if (!mounted ||
          widget.manager != manager ||
          _selectedStreamName != streamName) {
        return;
      }
      setState(() {
        _consumersError = describeJetStreamError(e);
        _loadingConsumers = false;
      });
    }
  }

  void _showAccountInfoDialog() {
    final manager = widget.manager;
    if (manager == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AccountInfoDialog(
        initial: manager.lastAccountInfo,
        onRefresh: manager.fetchAccountInfo,
      ),
    );
  }

  void _showConsumerDetail(ConsumerInfo info) {
    final isPush = (info.config.deliverSubject ?? '').isNotEmpty;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(info.name.isEmpty ? '(ephemeral consumer)' : info.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${isPush ? 'Push' : 'Pull'}'),
            Text('Ack Policy: ${info.config.ackPolicy}'),
            Text('Deliver Policy: ${info.config.deliverPolicy}'),
            if ((info.config.filterSubject ?? '').isNotEmpty)
              Text('Filter Subject: ${info.config.filterSubject}'),
            const SizedBox(height: 8),
            Text('Pending: ${info.numPending}'),
            Text('Waiting: ${info.numWaiting}'),
            Text('Ack Pending: ${info.numAckPending}'),
            Text('Redelivered: ${info.numRedelivered}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: info.name.isEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    _confirmDeleteConsumer(info.streamName, info.name);
                  },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: info.name.isEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    _tailConsumer(info);
                  },
            child: const Text('Tail'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _tailConsumer(ConsumerInfo info) {
    setState(() {
      _browsing = false;
      _tailingConsumerName = info.name;
      _tailingConsumerExplicitAck = info.config.ackPolicy == 'explicit';
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          // The theme's default SnackBar text color (`onSurface`) is only
          // guaranteed to contrast against the default background — once
          // an error swaps the background to `error`, the text must switch
          // to `onError` too, or it's unreadable (especially in dark mode,
          // where `error` is a light salmon and `onSurface` is near-white).
          style: isError ? TextStyle(color: colorScheme.onError) : null,
        ),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }

  Future<void> _runMutation(Future<void> Function() action,
      {required String successMessage}) async {
    if (_mutating) return;
    // A confirm dialog can be left open across a disconnect (e.g. the
    // connection drops while "Delete Stream?" is still showing) -- without
    // this, `action()`'s `widget.manager!` would throw an unhelpful "Null
    // check operator used on a null value" once the user finally confirms,
    // instead of a clean "not connected" message.
    if (widget.manager == null) {
      _showSnack('Not connected.', isError: true);
      return;
    }
    setState(() => _mutating = true);
    try {
      await action();
      if (!mounted) return;
      _showSnack(successMessage);
    } catch (e) {
      if (!mounted) return;
      _showSnack(describeJetStreamError(e), isError: true);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showCreateStreamDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => CreateStreamDialog(
        onCreate: (config) => _runMutation(
          () async {
            await widget.manager!.createStream(config);
            await _loadStreams();
          },
          successMessage: 'Stream "${config.name}" created.',
        ),
      ),
    );
  }

  void _confirmDeleteStream(String streamName) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stream?'),
        content: Text(
            'This permanently deletes "$streamName" and all of its messages. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _runMutation(
                () async {
                  await widget.manager!.deleteStream(streamName);
                  if (mounted) {
                    setState(() {
                      if (_selectedStreamName == streamName) {
                        _selectedStreamName = null;
                        _browsing = false;
                        _tailingConsumerName = null;
                      }
                    });
                  }
                  await _loadStreams();
                },
                successMessage: 'Stream "$streamName" deleted.',
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmPurgeStream(String streamName) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purge Stream?'),
        content: Text(
            'This permanently deletes all messages in "$streamName" but keeps '
            'the stream and its consumers. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _runMutation(
                () async {
                  await widget.manager!.purgeStream(streamName);
                  await _loadStreams();
                },
                successMessage: 'Stream "$streamName" purged.',
              );
            },
            child: const Text('Purge'),
          ),
        ],
      ),
    );
  }

  void _showCreateConsumerDialog(String streamName) {
    showDialog<void>(
      context: context,
      builder: (context) => CreateConsumerDialog(
        onCreate: (config) => _runMutation(
          () async {
            await widget.manager!.createConsumer(streamName, config);
            await _loadConsumers(streamName);
          },
          successMessage: 'Consumer created.',
        ),
      ),
    );
  }

  void _confirmDeleteConsumer(String streamName, String consumerName) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Consumer?'),
        content: Text('This permanently deletes consumer "$consumerName".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _runMutation(
                () async {
                  await widget.manager!
                      .deleteConsumer(streamName, consumerName);
                  if (mounted && _tailingConsumerName == consumerName) {
                    setState(() => _tailingConsumerName = null);
                  }
                  await _loadConsumers(streamName);
                },
                successMessage: 'Consumer "$consumerName" deleted.',
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message, {Widget? action}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }

  Widget _buildStreamList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Streams',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Account info',
                onPressed: _showAccountInfoDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh streams',
                onPressed: _loadingStreams ? null : _loadStreams,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Stream'),
            onPressed: _mutating ? null : _showCreateStreamDialog,
          ),
        ),
        const SizedBox(height: 4),
        if (_loadingStreams && _streams.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_streamsError != null)
          Expanded(
            child: _buildEmptyState(
              Icons.error_outline,
              _streamsError!,
              action: TextButton(
                  onPressed: _loadStreams, child: const Text('Retry')),
            ),
          )
        else if (_streams.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.inbox_outlined, 'No streams found on this account.'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _streams.length,
              itemBuilder: (context, index) {
                final stream = _streams[index];
                final selected = stream.config.name == _selectedStreamName;
                // `ListTile.selectedTileColor` is painted by the nearest
                // ancestor `Material` (here, the Scaffold's), not the tile
                // itself — on a long, fast-scrolling list that let the
                // highlight's ink decoration drift from the row it belonged
                // to and render over unrelated UI above the list. Giving
                // each row its own `Material` scopes that paint to the row.
                return Material(
                  key: ValueKey(stream.config.name),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .inversePrimary
                        .withAlpha(80),
                    title: Text(stream.config.name),
                    subtitle: Text(
                      '${stream.state.messages} msgs · ${formatBytes(stream.state.bytes)}',
                    ),
                    trailing: Chip(label: Text(stream.config.storage)),
                    onTap: () => _selectStream(stream.config.name),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildConsumerList(String streamName) {
    if (_loadingConsumers && _consumers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_consumersError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(_consumersError!)),
            TextButton(
              onPressed: () => _loadConsumers(streamName),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_consumers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No consumers on this stream yet.'),
      );
    }
    return Column(
      children: _consumers.map((consumer) {
        final isPush = (consumer.config.deliverSubject ?? '').isNotEmpty;
        return ListTile(
          dense: true,
          title: Text(consumer.name.isEmpty ? '(ephemeral)' : consumer.name),
          subtitle: Text(
            '${isPush ? 'Push' : 'Pull'} · Ack: ${consumer.config.ackPolicy} · '
            'Pending: ${consumer.numPending} · Redelivered: ${consumer.numRedelivered}',
          ),
          trailing: consumer.name.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete consumer',
                  onPressed: _mutating
                      ? null
                      : () => _confirmDeleteConsumer(
                          consumer.streamName, consumer.name),
                ),
          onTap: () => _showConsumerDetail(consumer),
        );
      }).toList(),
    );
  }

  Widget _buildStreamDetail(StreamInfo stream) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stream.config.name,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Storage: ${stream.config.storage}')),
              Chip(label: Text('Retention: ${stream.config.retention}')),
              Chip(label: Text('${stream.state.consumerCount} consumers')),
            ],
          ),
          const SizedBox(height: 8),
          Text('Subjects: ${stream.config.subjects.join(', ')}'),
          const SizedBox(height: 8),
          Text(
              'Messages: ${stream.state.messages}  ·  Size: ${formatBytes(stream.state.bytes)}'),
          Text(
            'First: ${formatRelativeTime(stream.state.firstTs)}  ·  '
            'Last: ${formatRelativeTime(stream.state.lastTs)}',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('Browse Messages'),
                onPressed: stream.state.messages == 0
                    ? null
                    : () => setState(() {
                          _browsing = true;
                          _tailingConsumerName = null;
                        }),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Purge'),
                onPressed: _mutating
                    ? null
                    : () => _confirmPurgeStream(stream.config.name),
              ),
              OutlinedButton.icon(
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                label: Text('Delete Stream',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: _mutating
                    ? null
                    : () => _confirmDeleteStream(stream.config.name),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Consumers',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create Consumer'),
                onPressed: _mutating
                    ? null
                    : () => _showCreateConsumerDialog(stream.config.name),
              ),
            ],
          ),
          const Divider(),
          _buildConsumerList(stream.config.name),
        ],
      ),
    );
  }

  Widget _buildDetailPane() {
    if (_selectedStreamName == null) {
      return _buildEmptyState(
          Icons.arrow_back, 'Select a stream to see details.');
    }

    if (_browsing) {
      return JetStreamMessageView(
        key: _browseViewKey,
        streamName: _selectedStreamName!,
        manager: widget.manager!,
        onClose: () => setState(() => _browsing = false),
      );
    }

    if (_tailingConsumerName != null) {
      return JetStreamConsumerTailView(
        key: ValueKey('$_selectedStreamName/$_tailingConsumerName'),
        streamName: _selectedStreamName!,
        consumerName: _tailingConsumerName!,
        explicitAck: _tailingConsumerExplicitAck,
        manager: widget.manager!,
        onClose: () => setState(() => _tailingConsumerName = null),
      );
    }

    final stream = _streams.where((s) => s.config.name == _selectedStreamName);
    if (stream.isEmpty) {
      return _buildEmptyState(
          Icons.error_outline, 'Stream not found. Try refreshing.');
    }
    return _buildStreamDetail(stream.first);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.manager == null) {
      return _buildEmptyState(
        Icons.cloud_off,
        'Connect to a NATS server to use JetStream.',
      );
    }

    if (_checkingAvailability) {
      return _buildEmptyState(
        Icons.hourglass_empty,
        'Checking JetStream availability...',
      );
    }

    if (_availabilityError != null) {
      return _buildEmptyState(
        Icons.error_outline,
        _availabilityError!,
        action: TextButton(
          onPressed: _checkAvailability,
          child: const Text('Retry'),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _buildStreamList()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildDetailPane()),
      ],
    );
  }
}
