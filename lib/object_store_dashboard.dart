import 'dart:io';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'jetstream_manager.dart' show formatBytes, formatRelativeTime;
import 'object_store_bucket_dialog.dart';
import 'object_store_manager.dart';

/// Real, `file_picker`-backed implementation of "pick a local file to
/// upload" — the default used outside of tests.
Future<(Uint8List, String)?> _defaultPickUploadFile() async {
  final result = await FilePicker.platform.pickFiles(withData: true);
  if (result == null) return null;
  final file = result.files.first;

  Uint8List? bytes = file.bytes;
  if (bytes == null && !kIsWeb && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null) return null;
  return (bytes, file.name);
}

/// Real, `file_picker`-backed implementation of "save these downloaded bytes
/// locally" — the default used outside of tests. On web, `saveFile` starts a
/// browser download directly from [bytes]; on desktop it opens a save
/// dialog and the bytes are written out separately, mirroring the split
/// `main.dart`'s own `pickFile()` already uses for the reverse (upload)
/// direction.
///
/// Returns whether a file was actually written -- on desktop, cancelling the
/// save dialog returns a `null` path with no exception thrown, which
/// previously fell through and reported a false "Downloaded" success with
/// nothing saved.
Future<bool> _defaultSaveDownloadedFile(
    String suggestedName, Uint8List bytes) async {
  if (kIsWeb) {
    await FilePicker.platform.saveFile(fileName: suggestedName, bytes: bytes);
    return true;
  }
  final path = await FilePicker.platform.saveFile(fileName: suggestedName);
  if (path == null) return false;
  await File(path).writeAsBytes(bytes);
  return true;
}

/// Object Store tab content: a monitor/management dashboard for Object
/// Store buckets and the objects (blobs) inside them, mirroring
/// `KvDashboard`'s master/detail shape.
///
/// Takes an already-constructed [ObjectStoreManager] (rather than a raw
/// `Client`) so tests can inject a fake manager and exercise the connected
/// dashboard states without a live NATS server. [pickUploadFile] and
/// [saveDownloadedFile] are similarly injectable, so upload/download flows
/// can be tested without touching the OS file picker.
class ObjectStoreDashboard extends StatefulWidget {
  /// The active Object Store manager, or `null` when not currently connected.
  final ObjectStoreManager? manager;

  final Future<(Uint8List, String)?> Function() pickUploadFile;
  final Future<bool> Function(String suggestedName, Uint8List bytes)
      saveDownloadedFile;

  const ObjectStoreDashboard({
    super.key,
    required this.manager,
    Future<(Uint8List, String)?> Function()? pickUploadFile,
    Future<bool> Function(String suggestedName, Uint8List bytes)?
        saveDownloadedFile,
  })  : pickUploadFile = pickUploadFile ?? _defaultPickUploadFile,
        saveDownloadedFile = saveDownloadedFile ?? _defaultSaveDownloadedFile;

  @override
  State<ObjectStoreDashboard> createState() => ObjectStoreDashboardState();
}

class ObjectStoreDashboardState extends State<ObjectStoreDashboard> {
  bool _checkingAvailability = false;
  String? _availabilityError;

  bool _loadingBuckets = false;
  String? _bucketsError;
  List<StreamInfo> _buckets = [];

  String? _selectedBucket;
  bool _loadingObjects = false;
  String? _objectsError;
  List<ObjectInfo> _objects = [];

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
  }

  @override
  void didUpdateWidget(covariant ObjectStoreDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager == widget.manager) return;

    if (widget.manager == null) {
      setState(() {
        _checkingAvailability = false;
        _availabilityError = null;
        _bucketsError = null;
        _buckets = [];
        _objects = [];
        _selectedBucket = null;
        _objectsError = null;
        _mutating = false;
      });
      return;
    }

    _checkAvailability();
  }

  @override
  void dispose() {
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
        _bucketsError = describeObjectStoreError(e);
        _loadingBuckets = false;
      });
    }
  }

  Future<void> _selectBucket(String bucket) async {
    setState(() {
      _selectedBucket = bucket;
      _objects = [];
      _objectsError = null;
      _searchController.clear();
    });
    await _loadObjects(bucket);
  }

  Future<void> _loadObjects(String bucket) async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _loadingObjects = true;
      _objectsError = null;
    });

    try {
      final objects = await manager.listObjects(bucket);
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
      setState(() {
        _objects = objects;
        _loadingObjects = false;
      });
    } catch (e) {
      if (!mounted || widget.manager != manager || _selectedBucket != bucket) {
        return;
      }
      setState(() {
        _objectsError = describeObjectStoreError(e);
        _loadingObjects = false;
      });
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          // See the identical comment in KvDashboard._showSnack: the
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
      _showSnack(describeObjectStoreError(e), isError: true);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  /// Shows a warn-and-proceed confirmation before a transfer larger than
  /// [largeObjectTransferWarningThreshold] -- the library buffers the whole
  /// object in memory for both directions, so this is the app-side mitigation
  /// noted on that constant's doc comment. Returns whether the user chose to
  /// continue.
  Future<bool> _confirmLargeTransfer(
      String verb, String name, int bytes) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Large $verb?'),
        content: Text(
            '"$name" is ${formatBytes(bytes)}. Large objects are held fully '
            'in memory during transfer and may be slow or use significant '
            'RAM. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(verb),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Confirms before an Upload overwrites an object name already present in
  /// the current listing -- today this happens silently, and the underlying
  /// library also leaves the previous object's chunks orphaned server-side
  /// (a library-level cleanup issue tracked separately on the roadmap).
  Future<bool> _confirmOverwrite(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Overwrite Object?'),
        content: Text(
            'An object named "$name" already exists in this bucket. '
            'Uploading will overwrite it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showCreateBucketDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => CreateObjectStoreBucketDialog(
        onCreate: (bucket, storage, replicas, maxBytes, ttl) => _runMutation(
          () async {
            await widget.manager!.createBucket(bucket,
                storage: storage,
                replicas: replicas,
                maxBytes: maxBytes,
                ttl: ttl);
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
            'This permanently deletes "$bucket" and all of its objects. '
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
                    setState(() {
                      _selectedBucket = null;
                      _objects = [];
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

  Future<void> _uploadFile(String bucket) async {
    final picked = await widget.pickUploadFile();
    if (picked == null || !mounted) return;
    final (bytes, name) = picked;

    final existing = _objects.where((o) => o.name == name);
    if (existing.isNotEmpty) {
      final confirmed = await _confirmOverwrite(name);
      if (!mounted || !confirmed) return;
    }

    if (bytes.length > largeObjectTransferWarningThreshold) {
      final confirmed =
          await _confirmLargeTransfer('Upload', name, bytes.length);
      if (!mounted || !confirmed) return;
    }

    await _runMutation(
      () async {
        await widget.manager!.putObject(bucket, name, bytes);
        await _loadObjects(bucket);
      },
      successMessage: 'Uploaded "$name".',
    );
  }

  Future<void> _downloadObject(String bucket, String name) async {
    final manager = widget.manager;
    if (manager == null) return;
    if (_mutating) return;

    final matches = _objects.where((o) => o.name == name);
    final info = matches.isEmpty ? null : matches.first;
    if (info != null && info.size > largeObjectTransferWarningThreshold) {
      final confirmed =
          await _confirmLargeTransfer('Download', name, info.size);
      if (!mounted || !confirmed) return;
    }

    setState(() => _mutating = true);
    try {
      final bytes = await manager.getObject(bucket, name);
      if (bytes == null) {
        // The library returns `null` both when the object was deleted *and*
        // on its own hardcoded 15s download timeout or a missing chunk
        // (verified against `dart_nats-1.2.2`'s `object_store.dart`) -- so
        // "no longer available" was misleading in the latter two cases.
        if (mounted) {
          _showSnack(
              '"$name" could not be downloaded — it may have been deleted, '
              'timed out, or is incomplete.',
              isError: true);
        }
        return;
      }
      final saved = await widget.saveDownloadedFile(name, bytes);
      // `saved` is false when the user cancels the save-file dialog --
      // previously this fell through and reported success with nothing
      // actually written to disk.
      if (mounted && saved) _showSnack('Downloaded "$name".');
    } catch (e) {
      if (mounted) _showSnack(describeObjectStoreError(e), isError: true);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _confirmDeleteObject(String bucket, String name) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Object?'),
        content: Text('This permanently deletes "$name". This cannot be undone.'),
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
                  await widget.manager!.deleteObject(bucket, name);
                  await _loadObjects(bucket);
                },
                successMessage: 'Object "$name" deleted.',
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
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh buckets',
                onPressed: _loadingBuckets ? null : _loadBuckets,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Object Store is an EXPERIMENTAL feature of the underlying NATS '
            'client library — behavior may change in future releases.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
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
            child: _buildEmptyState(Icons.inbox_outlined,
                'No Object Store buckets found on this account.'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _buckets.length,
              itemBuilder: (context, index) {
                final stream = _buckets[index];
                final bucket = bucketNameFromObjectStream(stream.config.name);
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
                      // Deliberately not "N objects": the backing stream's
                      // message count includes both metadata entries *and*
                      // chunk messages (an object over ~128 KiB spans
                      // several), so it overcounts the number of distinct
                      // objects a user would expect. "msgs" mirrors
                      // JetStreamDashboard's identical honesty about this
                      // being a raw stream metric, not a domain count.
                      '${stream.state.messages} msgs · ${formatBytes(stream.state.bytes)}',
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

  Widget _buildObjectRow(String bucket, ObjectInfo object) {
    final shortDigest = object.digest.length > 24
        ? '${object.digest.substring(0, 24)}…'
        : object.digest;
    return ListTile(
      title: Text(object.name),
      subtitle: Text(
        '${formatBytes(object.size)} · ${object.chunks} chunk${object.chunks == 1 ? '' : 's'} · '
        '$shortDigest\n'
        '${formatRelativeTime(object.mtime.toUtc().toIso8601String())}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: _mutating ? null : () => _downloadObject(bucket, object.name),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed:
                _mutating ? null : () => _confirmDeleteObject(bucket, object.name),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectList(String bucket) {
    final sortedObjects = [..._objects]..sort((a, b) => a.name.compareTo(b.name));
    final filteredObjects = _searchTerm.isEmpty
        ? sortedObjects
        : sortedObjects
            .where((o) => o.name.toLowerCase().contains(_searchTerm.toLowerCase()))
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
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh objects',
                onPressed: _loadingObjects ? null : () => _loadObjects(bucket),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
                onPressed: _mutating ? null : () => _uploadFile(bucket),
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
              hintText: 'Search objects',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingObjects && _objects.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_objectsError != null)
          Expanded(
            child: _buildEmptyState(
              Icons.error_outline,
              _objectsError!,
              action: TextButton(
                  onPressed: () => _loadObjects(bucket),
                  child: const Text('Retry')),
            ),
          )
        else if (_objects.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.folder_off_outlined, 'No objects in this bucket yet.'),
          )
        else if (filteredObjects.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.search_off, 'No objects match "$_searchTerm".'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filteredObjects.length,
              itemBuilder: (context, index) =>
                  _buildObjectRow(bucket, filteredObjects[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailPane() {
    if (_selectedBucket == null) {
      return _buildEmptyState(
          Icons.arrow_back, 'Select a bucket to see its objects.');
    }
    return _buildObjectList(_selectedBucket!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.manager == null) {
      return _buildEmptyState(
        Icons.cloud_off,
        'Connect to a NATS server to use Object Store.',
      );
    }

    if (_checkingAvailability) {
      return _buildEmptyState(
        Icons.hourglass_empty,
        'Checking Object Store availability...',
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
