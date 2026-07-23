import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'format_utils.dart' show formatConfiguredDuration;
import 'jetstream_manager.dart' show ConsumerDetail, describeJetStreamError;
import 'jetstream_pause_dialog.dart' show ConsumerPauseDurationDialog;

/// Read-only detail dialog for a single JetStream consumer -- type, ack/
/// deliver policy, filter subject, ack-wait/max-deliver/max-ack-pending, and
/// live pending/waiting/ack-pending/redelivered counters -- with its own
/// manual Refresh, since (unlike the rest of this dialog's fields) those
/// counters are a live snapshot that goes stale as soon as messages flow.
///
/// [initial] lets the caller show the `ConsumerInfo` it already has (from
/// the consumer list) without an extra round trip; [onRefresh] is called on
/// open (to pick up the ack-wait/max-deliver/max-ack-pending fields the list
/// view's plain `ConsumerInfo` doesn't carry) and again on every manual
/// Refresh tap, and after a successful [onPause]/[onResume] so the displayed
/// `paused`/`pauseUntil` state stays current without closing the dialog.
class ConsumerDetailDialog extends StatefulWidget {
  final ConsumerInfo initial;
  final Future<ConsumerDetail> Function() onRefresh;
  final VoidCallback? onDelete;
  final VoidCallback? onTail;
  final Future<void> Function(Duration pauseFor)? onPause;
  final Future<void> Function()? onResume;

  const ConsumerDetailDialog({
    super.key,
    required this.initial,
    required this.onRefresh,
    this.onDelete,
    this.onTail,
    this.onPause,
    this.onResume,
  });

  @override
  State<ConsumerDetailDialog> createState() => _ConsumerDetailDialogState();
}

class _ConsumerDetailDialogState extends State<ConsumerDetailDialog> {
  late ConsumerInfo _info;
  ConsumerDetail? _detail;
  bool _loading = false;
  String? _error;
  bool _pausing = false;

  @override
  void initState() {
    super.initState();
    _info = widget.initial;
    // An ephemeral consumer (no durable name) has nothing to refresh --
    // there's no name to address `$JS.API.CONSUMER.INFO.<stream>.<name>`
    // with, and it'll typically be gone by the time anyone reopens this
    // dialog anyway. Just show the static snapshot the list view already had.
    if (_info.name.isNotEmpty) _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _info = detail.info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeJetStreamError(e);
        _loading = false;
      });
    }
  }

  Future<void> _pause() async {
    final duration = await showDialog<Duration>(
      context: context,
      builder: (context) => ConsumerPauseDurationDialog(consumerName: _info.name),
    );
    if (duration == null || !mounted) return;
    setState(() {
      _pausing = true;
      _error = null;
    });
    try {
      await widget.onPause!(duration);
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeJetStreamError(e);
      });
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  Future<void> _resume() async {
    setState(() {
      _pausing = true;
      _error = null;
    });
    try {
      await widget.onResume!();
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeJetStreamError(e);
      });
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPush = (_info.config.deliverSubject ?? '').isNotEmpty;
    final detail = _detail;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child:
                Text(_info.name.isEmpty ? '(ephemeral consumer)' : _info.name),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh consumer info',
            onPressed: _loading || _info.name.isEmpty ? null : _refresh,
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${isPush ? 'Push' : 'Pull'}'),
            Text('Ack Policy: ${_info.config.ackPolicy}'),
            Text('Deliver Policy: ${_info.config.deliverPolicy}'),
            if ((_info.config.filterSubject ?? '').isNotEmpty)
              Text('Filter Subject: ${_info.config.filterSubject}'),
            if (_info.created.isNotEmpty) Text('Created: ${_info.created}'),
            if (detail?.ackWait != null)
              Text('Ack Wait: ${formatConfiguredDuration(detail!.ackWait!)}'),
            if (detail?.maxDeliver != null)
              Text(
                  'Max Deliver: ${detail!.maxDeliver == -1 ? 'unlimited' : detail.maxDeliver}'),
            if (detail?.maxAckPending != null)
              Text(
                  'Max Ack Pending: ${detail!.maxAckPending == -1 ? 'unlimited' : detail.maxAckPending}'),
            const SizedBox(height: 8),
            Text('Pending: ${_info.numPending}'),
            Text('Waiting: ${_info.numWaiting}'),
            Text('Ack Pending: ${_info.numAckPending}'),
            Text('Redelivered: ${_info.numRedelivered}'),
            if (_info.paused) ...[
              const SizedBox(height: 8),
              Text(
                detail?.pauseUntil != null
                    ? 'Paused until: ${detail!.pauseUntil!.toLocal()}'
                    : 'Paused',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (_info.paused)
          TextButton(
            onPressed:
                _pausing || _info.name.isEmpty || widget.onResume == null
                    ? null
                    : _resume,
            child: const Text('Resume'),
          )
        else
          TextButton(
            onPressed: _pausing || _info.name.isEmpty || widget.onPause == null
                ? null
                : _pause,
            child: const Text('Pause'),
          ),
        TextButton(
          onPressed: _info.name.isEmpty || widget.onDelete == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onDelete!();
                },
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: _info.name.isEmpty || widget.onTail == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onTail!();
                },
          child: const Text('Tail'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
