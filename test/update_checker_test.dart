import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nats_client_flutter/update_checker.dart';

void main() {
  group('isNewerVersion', () {
    test('returns true when the latest major version is higher', () {
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('returns true when the latest minor version is higher', () {
      expect(isNewerVersion('1.3.0', '1.2.9'), isTrue);
    });

    test('returns true when the latest patch version is higher', () {
      expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
    });

    test('compares numerically, not lexicographically', () {
      // a naive string comparison would say "1.2.9" > "1.2.10"
      expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
      expect(isNewerVersion('1.2.9', '1.2.10'), isFalse);
    });

    test('returns false when versions are equal', () {
      expect(isNewerVersion('1.2.3', '1.2.3'), isFalse);
    });

    test('returns false when the latest version is older', () {
      expect(isNewerVersion('1.0.0', '1.2.3'), isFalse);
    });

    test('ignores a build suffix after a plus sign', () {
      expect(isNewerVersion('1.2.3+4', '1.2.3+1'), isFalse);
      expect(isNewerVersion('1.3.0+1', '1.2.9+99'), isTrue);
    });

    test('treats missing trailing parts as zero', () {
      expect(isNewerVersion('1.3', '1.2.9'), isTrue);
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
    });
  });

  group('isStoreManagedInstall', () {
    test('Windows: true when the executable is under WindowsApps', () {
      expect(
        isStoreManagedInstall(
          operatingSystem: 'windows',
          resolvedExecutable:
              r'C:\Program Files\WindowsApps\9669NathanVerBeek.NATSClient_1.0.16.0_x64__abc123\nats_client_flutter.exe',
        ),
        isTrue,
      );
    });

    test('Windows: false for a direct-download install path', () {
      expect(
        isStoreManagedInstall(
          operatingSystem: 'windows',
          resolvedExecutable: r'C:\Users\nathan\Downloads\NATSClientUI\nats_client_flutter.exe',
        ),
        isFalse,
      );
    });

    test('Linux: true when the SNAP environment variable is set', () {
      expect(
        isStoreManagedInstall(
          operatingSystem: 'linux',
          environment: {'SNAP': '/snap/nats-client/42'},
        ),
        isTrue,
      );
    });

    test('Linux: false when the SNAP environment variable is absent', () {
      expect(
        isStoreManagedInstall(
          operatingSystem: 'linux',
          environment: {},
        ),
        isFalse,
      );
    });

    test('returns false on an unrecognized operating system', () {
      expect(isStoreManagedInstall(operatingSystem: 'macos'), isFalse);
    });
  });

  group('fetchLatestRelease', () {
    test('parses tag_name and html_url from a successful response', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/nverbeek/nats_client_flutter/releases/latest',
        );
        return http.Response(
          '{"tag_name": "v1.2.3", "html_url": "https://github.com/nverbeek/nats_client_flutter/releases/tag/v1.2.3"}',
          200,
        );
      });

      final release = await fetchLatestRelease(client: client);

      expect(release, isNotNull);
      expect(release!.version, '1.2.3');
      expect(release.htmlUrl,
          'https://github.com/nverbeek/nats_client_flutter/releases/tag/v1.2.3');
    });

    test('strips a leading v from the tag name', () async {
      final client = MockClient((request) async => http.Response(
          '{"tag_name": "v9.9.9", "html_url": "https://example.com"}', 200));

      final release = await fetchLatestRelease(client: client);

      expect(release!.version, '9.9.9');
    });

    test('leaves a tag name with no leading v untouched', () async {
      final client = MockClient((request) async => http.Response(
          '{"tag_name": "9.9.9", "html_url": "https://example.com"}', 200));

      final release = await fetchLatestRelease(client: client);

      expect(release!.version, '9.9.9');
    });

    test('returns null on a non-200 response', () async {
      final client =
          MockClient((request) async => http.Response('Not Found', 404));

      final release = await fetchLatestRelease(client: client);

      expect(release, isNull);
    });

    test('returns null on malformed JSON', () async {
      final client =
          MockClient((request) async => http.Response('not json', 200));

      final release = await fetchLatestRelease(client: client);

      expect(release, isNull);
    });

    test('returns null when tag_name is missing', () async {
      final client = MockClient((request) async =>
          http.Response('{"html_url": "https://example.com"}', 200));

      final release = await fetchLatestRelease(client: client);

      expect(release, isNull);
    });

    test('returns null when the request throws', () async {
      final client = MockClient((request) async {
        throw const SocketExceptionStub();
      });

      final release = await fetchLatestRelease(client: client);

      expect(release, isNull);
    });
  });
}

/// A stand-in for a network failure (e.g. SocketException) that doesn't
/// require pulling in dart:io just for the test.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
