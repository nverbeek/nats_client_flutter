import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'account_info_dialog.dart';
import 'format_utils.dart';
import 'jetstream_manager.dart' show formatBytes, formatRelativeTime;
import 'kv_bucket_dialog.dart';
import 'kv_manager.dart';
import 'kv_put_dialog.dart';

/// Key-Value tab content: a monitor/management dashboard for KV buckets and
/// their keys, mirroring `JetStreamDashboard`'s master/detail shape.
///
/// Takes an already-constructed [KvManager] (rather than a raw `Client`) so
/// tests can inject a fake manager and exercise the connected dashboard
/// states without a live NATS server.
class KvDashboard extends StatefulWidget {
  /// The active KV manager, or `null` when not currently connected.
  final KvManager? manager;

  /// Fires after a real reconnect -- see `JetStreamDashboard`'s doc comment
  /// on the same parameter for why this needs its own signal rather than a
  /// `didUpdateWidget` check on `manager`. Optional so tests that never
  /// disconnect don't need to plumb one through.
  final Listenable? reconnectSignal;

  const KvDashboard(
      {super.key, required this.manager, this.reconnectSignal});

  @override
  State<KvDashboard> createState() => KvDashboardState();
}

class KvDashboardState extends State<KvDashboard> {
  bool _checkingAvailability = false;
  String? _availabilityError;

  bool _loadingBuckets = false;
  String? _bucketsError;
  List<StreamInfo> _buckets = [];

  String? _selectedBucket;
  bool _loadingKeys = false;
  String? _keysError;
  final Map<String, KeyValueEntry> _entries = {};
  StreamSubscription<KeyValueEntry?>? _watchSub;

  bool _mutating = false;

  final _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchTerm = _searchController.text.trim());
    });
    if (widget.manager != null) {
      _checkAvailability();
    }
    widget.reconnectSignal?.addListener(_onReconnect);
  }

  /// Unlike the JetStream dashboards, a KV watch's own subscription is a
  /// plain core-NATS subscription -- `dart_nats` already resends `SUB` for
  /// it on reconnect (see `Client._backendSubscriptAll`), so it silently
  /// keeps working with no error and no app-side action needed. The real gap
  /// is what happened *during* the disconnect: `watch()`'s ephemeral
  /// consumer is `deliverPolicy: 'last'`, so a put/delete that landed while
  /// disconnected is invisible until a fresh snapshot -- there's no
  /// resume-from-last-seen option to backfill it otherwise. So this
  /// re-snapshots the selected bucket (which also restarts the watch as
  /// `_loadKeys`'s last step) rather than only doing so when `_keysError`
  /// happens to be set.
  ///
  /// The re-snapshot is gated on one cheap `bucketStatus` request first,
  /// though: it costs one round trip and tells us the backing stream's last
  /// sequence, and since KV revisions *are* stream sequences, that matching
  /// the highest revision we already hold means nothing was written while
  /// we were away and the (still-live) watch has us covered. Without that
  /// gate, every reconnect blip on a large bucket re-fetched every key --
  /// thousands of requests, and repeatedly, since a flaky link is exactly
  /// what produces repeated reconnects.
  Future<void> _onReconnect() async {
    final manager = widget.manager;
    if (manager == null) return;
    if (_availabilityError != null) {
      _checkAvailability();
      return;
    }
    if (_bucketsError != null) {
      _loadBuckets();
    }
    final bucket = _selectedBucket;
    if (bucket == null) return;

    // An errored key list has no trustworthy high-water mark to compare
    // against, so always do the full reload in that case.
    if (_keysError == null && _entries.isNotEmpty) {
      try {
        final status = await manager.bucketStatus(bucket);
        if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
          return;
        }
        final highestHeld = _entries.values
            .fold<int>(0, (max, e) => e.revision > max ? e.revision : max);
        if (status.lastSeq == highestHeld) return;
      } catch (_) {
        // Fall through to the full reload -- the probe is an optimization,
        // never a reason to skip recovery.
      }
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
    }
    _loadKeys(bucket);
  }

  @override
  void didUpdateWidget(covariant KvDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager == widget.manager) return;

    if (widget.manager == null) {
      _watchSub?.cancel();
      _watchSub = null;
      setState(() {
        _checkingAvailability = false;
        _availabilityError = null;
        _bucketsError = null;
        _buckets = [];
        _entries.clear();
        _selectedBucket = null;
        _keysError = null;
        _mutating = false;
      });
      return;
    }

    _checkAvailability();
  }

  @override
  void dispose() {
    widget.reconnectSignal?.removeListener(_onReconnect);
    _watchSub?.cancel();
    _searchController.dispose();
    super.dispose();
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
      _loadBuckets();
    }
  }

  Future<void> _loadBuckets() async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _loadingBuckets = true;
      _bucketsError = null;
    });

    try {
      final buckets = await manager.listBuckets();
      if (!mounted || widget.manager != manager) return;
      setState(() {
        _buckets = buckets;
        _loadingBuckets = false;
      });
    } catch (e) {
      if (!mounted || widget.manager != manager) return;
      setState(() {
        _bucketsError = describeKvError(e);
        _loadingBuckets = false;
      });
    }
  }

  Future<void> _selectBucket(String bucket) async {
    _watchSub?.cancel();
    _watchSub = null;
    setState(() {
      _selectedBucket = bucket;
      _entries.clear();
      _keysError = null;
      _searchController.clear();
    });
    await _loadKeys(bucket);
  }

  Future<void> _loadKeys(String bucket) async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _loadingKeys = true;
      _keysError = null;
    });

    try {
      final keys = await manager.listKeys(bucket);
      final entries = await _fetchEntriesBatched(manager, bucket, keys);
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
      setState(() {
        _entries.clear();
        for (final entry in entries) {
          if (entry != null) _entries[entry.key] = entry;
        }
        _loadingKeys = false;
      });
      _startWatch(bucket);
    } catch (e) {
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
      setState(() {
        _keysError = describeKvError(e);
        _loadingKeys = false;
      });
    }
  }

  /// Fetches each key's entry in bounded-concurrency batches rather than
  /// firing every `getEntry` request at once via a single `Future.wait` --
  /// a bucket with thousands of keys would otherwise storm the client/server
  /// with that many simultaneous in-flight requests.
  Future<List<KeyValueEntry?>> _fetchEntriesBatched(
      KvManager manager, String bucket, List<String> keys,
      {int batchSize = 16}) async {
    final results = <KeyValueEntry?>[];
    for (var i = 0; i < keys.length; i += batchSize) {
      final end = (i + batchSize < keys.length) ? i + batchSize : keys.length;
      final chunkResults = await Future.wait(keys.sublist(i, end).map((k) async {
        try {
          return await manager.getEntry(bucket, k);
        } catch (_) {
          return null;
        }
      }));
      results.addAll(chunkResults);
    }
    return results;
  }

  void _startWatch(String bucket) {
    final manager = widget.manager;
    if (manager == null) return;

    // `_loadKeys` calls this on every successful load, including a Retry
    // that doesn't go through `_selectBucket` (which cancels first) -- so a
    // retry (or any other refresh path) without this would leave the
    // previous watch subscription running underneath the new one, stacking
    // a duplicate client-side listener per refresh.
    _watchSub?.cancel();

    _watchSub = manager.watch(bucket).listen((entry) {
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
      if (entry == null) return;
      setState(() {
        if (entry.op == KeyValueOp.put) {
          _entries[entry.key] = entry;
        } else {
          _entries.remove(entry.key);
        }
      });
    }, onError: (Object err) {
      // Without this, an error on the watch stream (a parse failure, the
      // underlying subscription erroring, or the ephemeral watch consumer
      // failing to create) would be an uncaught zone error that silently
      // ends the subscription -- the key list would stop reflecting live
      // changes from other clients while still looking perfectly healthy.
      // Surfacing it through the same `_keysError`/Retry path `_loadKeys`
      // already uses lets the user recover the same way a load failure
      // would. Explicitly cancel (not just null out the reference) so the
      // errored subscription doesn't linger uncancelled underneath a later
      // `_startWatch` call -- `.cancel()` from within a stream's own
      // `onError` callback is safe; by the time this fires, `_watchSub`
      // already points at this exact subscription.
      _watchSub?.cancel();
      _watchSub = null;
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
      setState(() {
        _keysError = describeKvError(err);
      });
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          // See the identical comment in JetStreamDashboard._showSnack: the
          // theme's default SnackBar text color only contrasts against the
          // default background, so an error background needs `onError` text.
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
    // connection drops while "Delete Bucket?" is still showing) -- without
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
      _showSnack(describeKvError(e), isError: true);
    } finally {
      if (mounted) setState(() => _mutating = false);
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

  void _showCreateBucketDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => CreateBucketDialog(
        onCreate: (bucket, history, ttl, replicas) => _runMutation(
          () async {
            await widget.manager!.createBucket(bucket,
                history: history, ttl: ttl, replicas: replicas);
            await _loadBuckets();
          },
          successMessage: 'Bucket "$bucket" created.',
        ),
      ),
    );
  }

  void _confirmDeleteBucket(String bucket) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bucket?'),
        content: Text(
            'This permanently deletes "$bucket" and all of its keys. '
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
                  await widget.manager!.deleteBucket(bucket);
                  if (mounted && _selectedBucket == bucket) {
                    _watchSub?.cancel();
                    _watchSub = null;
                    setState(() {
                      _selectedBucket = null;
                      _entries.clear();
                    });
                  }
                  await _loadBuckets();
                },
                successMessage: 'Bucket "$bucket" deleted.',
              );
            },
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showPutDialog(String bucket, {KeyValueEntry? existing}) {
    showDialog<void>(
      context: context,
      builder: (context) => KvPutValueDialog(
        bucket: bucket,
        initialKey: existing?.key,
        initialValue: existing == null ? null : decodeMessageText(existing.value),
        existingRevision: existing?.revision,
        onSave: (key, value, expectedRevision) => _runMutation(
          () async {
            final int revision;
            if (expectedRevision != null) {
              revision = await widget.manager!
                  .updateValue(bucket, key, value, expectedRevision);
            } else {
              revision = await widget.manager!.putValue(bucket, key, value);
            }
            // Apply the result locally rather than waiting on the watch
            // stream to echo it back -- a Put/Edit should be reflected
            // immediately regardless of watch latency (or a dead watch, see
            // `_startWatch`'s `onError`), matching how Delete/Purge already
            // update `_entries` directly below.
            if (mounted) {
              setState(() {
                _entries[key] = KeyValueEntry(
                  bucket: bucket,
                  key: key,
                  value: Uint8List.fromList(utf8.encode(value)),
                  revision: revision,
                  created: DateTime.now(),
                );
              });
            }
          },
          successMessage: expectedRevision != null
              ? 'Key "$key" updated.'
              : 'Key "$key" saved.',
        ),
      ),
    );
  }

  void _confirmDeleteKey(String bucket, String key) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Key?'),
        content: Text('This deletes "$key" (its history is kept).'),
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
                  await widget.manager!.deleteKey(bucket, key);
                  if (mounted) setState(() => _entries.remove(key));
                },
                successMessage: 'Key "$key" deleted.',
              );
            },
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmPurgeKey(String bucket, String key) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purge Key?'),
        content: Text(
            'This permanently removes all history for "$key". This cannot be undone.'),
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
                  await widget.manager!.purgeKey(bucket, key);
                  if (mounted) setState(() => _entries.remove(key));
                },
                successMessage: 'Key "$key" purged.',
              );
            },
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Purge'),
          ),
        ],
      ),
    );
  }

  void _showBucketInfoDialog(String bucket) {
    final manager = widget.manager;
    if (manager == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => KvBucketStatusDialog(
        bucket: bucket,
        onRefresh: () => manager.bucketStatus(bucket),
      ),
    );
  }

  void _showHistoryDialog(String bucket, String key) async {
    final manager = widget.manager;
    if (manager == null) return;

    showDialog<void>(
      context: context,
      builder: (context) => FutureBuilder<List<KeyValueEntry>>(
        future: manager.keyHistory(bucket, key),
        builder: (context, snapshot) {
          Widget content;
          if (snapshot.connectionState != ConnectionState.done) {
            content = const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            content = Text(describeKvError(snapshot.error!));
          } else {
            final history = snapshot.data!.reversed.toList();
            content = SizedBox(
              width: 400,
              height: 300,
              child: history.isEmpty
                  ? const Center(child: Text('No history available.'))
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final entry = history[index];
                        return ListTile(
                          dense: true,
                          title: Text('Rev #${entry.revision} — ${entry.op.name}'),
                          subtitle: Text(
                            entry.op == KeyValueOp.put
                                ? decodeMessageText(entry.value)
                                : '(no value)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
            );
          }
          return AlertDialog(
            title: Text('History: $key'),
            content: content,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
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

  Widget _buildBucketList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Buckets',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Account info',
                onPressed: _showAccountInfoDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh buckets',
                onPressed: _loadingBuckets ? null : _loadBuckets,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Bucket'),
            onPressed: _mutating ? null : _showCreateBucketDialog,
          ),
        ),
        const SizedBox(height: 4),
        if (_loadingBuckets && _buckets.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_bucketsError != null)
          Expanded(
            child: _buildEmptyState(
              Icons.error_outline,
              _bucketsError!,
              action: TextButton(
                  onPressed: _loadBuckets, child: const Text('Retry')),
            ),
          )
        else if (_buckets.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.inbox_outlined, 'No KV buckets found on this account.'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _buckets.length,
              itemBuilder: (context, index) {
                final stream = _buckets[index];
                final bucket = bucketNameFromStream(stream.config.name);
                final selected = bucket == _selectedBucket;
                // See `JetStreamDashboard`'s identical comment: scope the
                // selection-highlight paint to this row via its own
                // `Material`, rather than letting it drift on a fast list.
                return Material(
                  key: ValueKey(bucket),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .inversePrimary
                        .withAlpha(80),
                    title: Text(bucket),
                    subtitle: Text(
                      '${stream.state.messages} ops · ${formatBytes(stream.state.bytes)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete bucket',
                      onPressed: _mutating
                          ? null
                          : () => _confirmDeleteBucket(bucket),
                    ),
                    onTap: () => _selectBucket(bucket),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Row action menu items, shared by the trailing overflow button and the
  /// row's right-click context menu -- mirrors the split done for Live
  /// Messages (`main.dart`), JetStream Browse Messages
  /// (`jetstream_message_view.dart`), and JetStream Consumer Tail
  /// (`jetstream_consumer_tail_view.dart`).
  List<PopupMenuEntry<String>> _buildRowMenuItems(BuildContext context) {
    return const [
      PopupMenuItem(value: 'edit', child: Text('Edit')),
      PopupMenuItem(value: 'history', child: Text('History')),
      PopupMenuItem(value: 'delete', child: Text('Delete')),
      PopupMenuItem(value: 'purge', child: Text('Purge')),
    ];
  }

  void _handleRowMenuSelection(
      String value, String bucket, KeyValueEntry entry) {
    switch (value) {
      case 'edit':
        _showPutDialog(bucket, existing: entry);
        break;
      case 'history':
        _showHistoryDialog(bucket, entry.key);
        break;
      case 'delete':
        _confirmDeleteKey(bucket, entry.key);
        break;
      case 'purge':
        _confirmPurgeKey(bucket, entry.key);
        break;
    }
  }

  /// Opens the same row action menu as the trailing overflow button, but
  /// anchored at [globalPosition] -- see the matching `_showRowContextMenu`
  /// in `main.dart` for why (right-click should open at the cursor, not
  /// jump to the row's trailing edge). A no-op while a mutation is already
  /// in flight, mirroring the trailing `PopupMenuButton`'s own
  /// `enabled: !_mutating`.
  Future<void> _showRowContextMenu(BuildContext context, String bucket,
      KeyValueEntry entry, Offset globalPosition) async {
    if (_mutating) return;
    final items = _buildRowMenuItems(context);
    if (items.isEmpty) return;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: items,
    );
    if (selected != null) {
      _handleRowMenuSelection(selected, bucket, entry);
    }
  }

  Widget _buildKeyRow(String bucket, KeyValueEntry entry) {
    return GestureDetector(
      key: ValueKey('kv_row_${entry.key}'),
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          _showRowContextMenu(context, bucket, entry, details.globalPosition),
      child: ListTile(
        title: Text(entry.key),
        subtitle: Text(
          '${decodeMessageText(entry.value)}\n'
          'Rev #${entry.revision} · ${formatRelativeTime(entry.created.toIso8601String())}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          enabled: !_mutating,
          tooltip: 'More actions',
          onSelected: (action) => _handleRowMenuSelection(action, bucket, entry),
          itemBuilder: _buildRowMenuItems,
        ),
        onTap: () => _showPutDialog(bucket, existing: entry),
      ),
    );
  }

  Widget _buildKeyList(String bucket) {
    final sortedKeys = _entries.keys.toList()..sort();
    final filteredKeys = _searchTerm.isEmpty
        ? sortedKeys
        : sortedKeys
            .where((k) =>
                k.toLowerCase().contains(_searchTerm.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(bucket, style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Bucket info',
                onPressed: () => _showBucketInfoDialog(bucket),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh keys',
                onPressed: _loadingKeys ? null : () => _loadKeys(bucket),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Put Value'),
                onPressed: _mutating ? null : () => _showPutDialog(bucket),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
              hintText: 'Search keys',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingKeys && _entries.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_keysError != null)
          Expanded(
            child: _buildEmptyState(
              Icons.error_outline,
              _keysError!,
              action: TextButton(
                  onPressed: () => _loadKeys(bucket),
                  child: const Text('Retry')),
            ),
          )
        else if (_entries.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.key_off_outlined, 'No keys in this bucket yet.'),
          )
        else if (filteredKeys.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.search_off, 'No keys match "$_searchTerm".'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filteredKeys.length,
              itemBuilder: (context, index) =>
                  _buildKeyRow(bucket, _entries[filteredKeys[index]]!),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailPane() {
    if (_selectedBucket == null) {
      return _buildEmptyState(
          Icons.arrow_back, 'Select a bucket to see its keys.');
    }
    return _buildKeyList(_selectedBucket!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.manager == null) {
      return _buildEmptyState(
        Icons.cloud_off,
        'Connect to a NATS server to use Key-Value stores.',
      );
    }

    if (_checkingAvailability) {
      return _buildEmptyState(
        Icons.hourglass_empty,
        'Checking Key-Value availability...',
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
        SizedBox(width: 320, child: _buildBucketList()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildDetailPane()),
      ],
    );
  }
}
