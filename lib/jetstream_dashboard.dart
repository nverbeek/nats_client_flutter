import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'jetstream_manager.dart';
import 'jetstream_message_view.dart';

/// JetStream tab content: a read-only monitor for streams and consumers,
/// plus a live "Browse Messages" tail for a selected stream.
///
/// Milestone 1a is intentionally read-only — no stream/consumer mutations —
/// so this widget only ever calls list/info methods on [JetStreamManager].
///
/// Takes an already-constructed [JetStreamManager] (rather than a raw
/// `Client`) so tests can inject a fake manager and exercise the connected
/// dashboard states without a live NATS server.
class JetStreamDashboard extends StatefulWidget {
  /// The active JetStream manager, or `null` when not currently connected.
  final JetStreamManager? manager;

  const JetStreamDashboard({super.key, required this.manager});

  @override
  State<JetStreamDashboard> createState() => _JetStreamDashboardState();
}

class _JetStreamDashboardState extends State<JetStreamDashboard> {
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh streams',
                onPressed: _loadingStreams ? null : _loadStreams,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
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
                return ListTile(
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
          ElevatedButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Browse Messages'),
            onPressed: stream.state.messages == 0
                ? null
                : () => setState(() => _browsing = true),
          ),
          const SizedBox(height: 24),
          Text('Consumers', style: Theme.of(context).textTheme.titleMedium),
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
        key: ValueKey(_selectedStreamName),
        streamName: _selectedStreamName!,
        manager: widget.manager!,
        onClose: () => setState(() => _browsing = false),
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
