import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;

/// Seeds a demo Object Store bucket with realistic objects, used by
/// `object_store_demo.ps1` for the README screenshot tour.
///
/// Deliberately goes through `dart_nats`'s own `ObjectStore.put()` — the
/// same call the app's own Upload button makes — rather than the `nats`
/// CLI's `object put`. The CLI's own object metadata writer leaves `mtime`
/// unset (Go's zero-value time, `0001-01-01T00:00:00Z`), which `dart_nats`
/// parses as a technically-valid but absurd date; the app's relative-time
/// display then shows something like "739807d ago" instead of "just now".
/// Confirmed via `nats sub '$O.<bucket>.M.>'` against a real server: the raw
/// metadata JSON really does contain that zero-value `mtime`, even though
/// the CLI's own `nats object info` shows a correct-looking timestamp
/// (derived from elsewhere, not the field this app's `ObjectInfo.fromJson`
/// reads). Seeding through the same client code path the app itself uses
/// sidesteps the whole mismatch.
///
/// Usage: `dart run --packages=.dart_tool/package_config.json
/// scripts/seed_object_store.dart HOST PORT BUCKET ICON_FILE_PATH`
Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? args[1] : '4222';
  final bucket = args.length > 2 ? args[2] : 'documents';
  final iconPath = args.length > 3 ? args[3] : null;

  final client = Client();
  await client.connect(Uri.parse('nats://$host:$port'));

  final js = client.jetStream();
  try {
    await js.deleteObjectStore(bucket);
  } catch (_) {
    // Bucket didn't already exist — fine, this is best-effort cleanup so
    // re-runs start from a clean bucket instead of accumulating objects.
  }
  await js.createObjectStore(ObjectStoreConfig(bucket: bucket));
  final store = ObjectStore(client, bucket);

  if (iconPath != null) {
    final bytes = await File(iconPath).readAsBytes();
    await store.put('app-icon.svg', bytes);
  }

  await store.putString('release-notes.md', '''
# Release Notes

## v1.0.13
- Added the Object Store Inspector: browse, upload, download, and delete
  objects in JetStream-backed Object Store buckets.
- Object list is refreshed on demand (Object Store has no live-update
  mechanism, unlike Key-Value Stores).
''');

  await store.putString('server-config.json', '''
{
  "environment": "production",
  "region": "us-east-1",
  "maxConnections": 500,
  "featureFlags": {
    "objectStore": true,
    "queueGroups": false
  }
}
''');

  // A larger, multi-chunk object (Object Store chunks at 128 KiB) so the
  // screenshot's chunk-count column shows something other than "1 chunk".
  final random = Random();
  final bundleBytes = Uint8List(200 * 1024);
  for (var i = 0; i < bundleBytes.length; i++) {
    bundleBytes[i] = random.nextInt(256);
  }
  await store.put('diagnostics-bundle.tar.gz', bundleBytes);

  client.close();
}
