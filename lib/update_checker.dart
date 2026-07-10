import 'dart:convert';

import 'package:http/http.dart' as http;

/// GitHub repo this app publishes releases to (see [README.md]'s build badge).
const String githubOwner = 'nverbeek';
const String githubRepo = 'nats_client_flutter';

const String _latestReleaseUrl =
    'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

/// The published release this app would offer to send the user to.
class ReleaseInfo {
  /// Version number with any leading `v` stripped (e.g. `1.2.0`).
  final String version;

  /// The GitHub release page to open (e.g. `.../releases/tag/v1.2.0`).
  final String htmlUrl;

  const ReleaseInfo({required this.version, required this.htmlUrl});
}

/// Fetches the latest published GitHub release for this project.
///
/// Returns null if the request fails, times out, or the response can't be
/// parsed — this is a best-effort background check, not a critical
/// operation, so failures are swallowed rather than surfaced to the user.
/// [client] can be supplied in tests to avoid a real network call.
Future<ReleaseInfo?> fetchLatestRelease({http.Client? client}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(
          Uri.parse(_latestReleaseUrl),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      return null;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = json['tag_name'] as String?;
    final htmlUrl = json['html_url'] as String?;
    if (tagName == null || tagName.isEmpty || htmlUrl == null) {
      return null;
    }

    return ReleaseInfo(
      version: tagName.startsWith('v') ? tagName.substring(1) : tagName,
      htmlUrl: htmlUrl,
    );
  } catch (_) {
    return null;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}

/// Parses a dotted version string (e.g. `1.2.10`, ignoring any `+build`
/// suffix) into its numeric parts. Non-numeric parts default to 0.
List<int> _parseVersionParts(String version) {
  final withoutBuild = version.split('+').first;
  return withoutBuild
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
}

/// Returns true if [latest] is a newer version than [current]. Compares
/// dotted numeric version parts (so `1.2.10` > `1.2.9`, unlike a plain
/// string comparison), treating missing trailing parts as 0.
bool isNewerVersion(String latest, String current) {
  final latestParts = _parseVersionParts(latest);
  final currentParts = _parseVersionParts(current);
  final length = latestParts.length > currentParts.length
      ? latestParts.length
      : currentParts.length;

  for (var i = 0; i < length; i++) {
    final l = i < latestParts.length ? latestParts[i] : 0;
    final c = i < currentParts.length ? currentParts[i] : 0;
    if (l != c) {
      return l > c;
    }
  }
  return false;
}
