import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// File-based handshake between this integration test (running inside the
/// real Flutter app process, driven by `flutter test ... -d windows`) and
/// `scripts/capture_screenshots.ps1` (a separate host process). A real,
/// title-bar-and-all window screenshot can only be taken from outside the
/// Flutter engine process — see that script for the actual Win32 capture —
/// so the two processes hand off turns through plain files rather than a
/// socket or platform channel: it behaves the same whether the watcher on
/// the other end is PowerShell, a different shell script, or a human
/// dropping files in by hand.
class ScreenshotSignaler {
  ScreenshotSignaler([String? signalDirPath])
      : dir = Directory(signalDirPath ??
            '${Directory.current.path}/build/.screenshot_signals') {
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  final Directory dir;

  File get _requestFile => File('${dir.path}/request.txt');
  File _doneFile(String name) => File('${dir.path}/done_$name.flag');
  File get _seedRequestFile => File('${dir.path}/seed_request.flag');
  File get _seedDoneFile => File('${dir.path}/seed_done.flag');

  Future<void> _waitForFile(
    File file, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!file.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
            'Timed out waiting for ${file.path}. Is '
            'scripts/capture_screenshots.ps1 running and watching '
            '${dir.path}?',
            timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Asks the orchestrator to publish the sample Live Messages payloads
  /// (`scripts/message_pub.ps1`) now that the app is connected and
  /// subscribed. Core NATS pub/sub has no history — publishing any earlier
  /// than this would be silently lost since nothing was subscribed yet.
  Future<void> requestSeedMessages() async {
    if (_seedDoneFile.existsSync()) _seedDoneFile.deleteSync();
    _seedRequestFile.writeAsStringSync('go');
    await _waitForFile(_seedDoneFile, timeout: const Duration(seconds: 30));
  }

  /// Asks the orchestrator to capture the current app window under [name]
  /// and waits for confirmation that the file was written to disk before
  /// letting the test move on to change the screen underneath it.
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final done = _doneFile(name);
    if (done.existsSync()) done.deleteSync();
    _requestFile.writeAsStringSync(name);
    await _waitForFile(done);
  }
}
