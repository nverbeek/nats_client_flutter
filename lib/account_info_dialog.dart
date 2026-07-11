import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'jetstream_manager.dart' show describeJetStreamError, formatBytes;

/// Read-only dialog showing a JetStream account's usage/limits snapshot.
///
/// Shared by both the JetStream and KV dashboards — `AccountInfo` describes
/// the whole account, not a specific stream or bucket, so there's nothing
/// dashboard-specific about it. [initial] lets the caller show data that's
/// already been fetched (both dashboards fetch it for free as a side effect
/// of their own availability check) without an extra round trip; [onRefresh]
/// is only called if [initial] is `null` or the user taps Refresh.
class AccountInfoDialog extends StatefulWidget {
  final AccountInfo? initial;
  final Future<AccountInfo> Function() onRefresh;

  const AccountInfoDialog(
      {super.key, required this.initial, required this.onRefresh});

  @override
  State<AccountInfoDialog> createState() => _AccountInfoDialogState();
}

class _AccountInfoDialogState extends State<AccountInfoDialog> {
  AccountInfo? _info;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _info = widget.initial;
    if (_info == null) _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _info = info;
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

  Widget _usageRow(String label, int used, int reserved) {
    // A reserved limit of 0 means "no limit configured". A server also
    // represents "unlimited" as a uint64 -1 sentinel for some fields (e.g.
    // `reserved_storage`), which after JSON round-tripping through a double
    // and back arrives as a huge but finite int — treat anything absurdly
    // larger than any real quota as unlimited too, rather than rendering a
    // multi-exabyte "reserved" figure.
    final unlimited = reserved <= 0 || reserved >= (1 << 62);
    final ratio = unlimited ? 0.0 : (used / reserved).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          unlimited
              ? '$label: ${formatBytes(used)}'
              : '$label: ${formatBytes(used)} / ${formatBytes(reserved)}',
        ),
        if (!unlimited) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: ratio, minHeight: 6),
          ),
        ],
      ],
    );
  }

  Widget _buildContent() {
    if (_loading && _info == null) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _info == null) {
      return Text(_error!);
    }

    final info = _info!;
    final tier = info.tier;
    final api = info.api;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.domain.isNotEmpty) ...[
          Text('Domain: ${info.domain}'),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('${tier.streams} streams')),
            Chip(label: Text('${tier.consumers} consumers')),
          ],
        ),
        const SizedBox(height: 16),
        _usageRow('Memory', tier.memory, tier.reservedMemory),
        const SizedBox(height: 12),
        _usageRow('Storage', tier.storage, tier.reservedStorage),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text('API calls: ${api.total}  ·  errors: ${api.errors}  ·  '
            'in-flight: ${api.inflight}'),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Account Info')),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh account info',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      content: SizedBox(width: 360, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
