import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Proves the macOS build's App Sandbox still lets file_picker's native
/// Open/Save panels grant access to user-chosen files outside the app's
/// container — the access every file-based feature relies on (TLS cert/key
/// and `.creds` picks, Export, Replay, Object Store upload/download).
///
/// Uses the same calls the app does (`pickFiles` + `File.readAsBytes`,
/// `saveFile` + `File.writeAsBytes`), not the app's UI, since the native
/// panel is the thing under test. Nothing running inside the sandboxed app
/// can click a panel it opened itself, so CI's `test-macos` job starts
/// `scripts/ci/drive_macos_file_panel.applescript` in the background first;
/// that script answers each panel by typing a path into it, then this test
/// checks the result.
///
/// macOS-only, and only meaningful under that CI job: it needs
/// `SANDBOX_PROBE_DIR` (a directory outside the app container, holding a
/// `probe.pem` the CI step wrote) and `SANDBOX_PROBE_CONTENT` (that file's
/// contents) passed via `--dart-define`.
/// How long to wait for the CI driver to answer each panel.
const _panelTimeout = Duration(minutes: 2);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const probeDir = String.fromEnvironment('SANDBOX_PROBE_DIR');
  const probeContent = String.fromEnvironment('SANDBOX_PROBE_CONTENT');

  testWidgets(
    'native Open/Save panels grant sandboxed access outside the container',
    (tester) async {
      final probePath = '$probeDir/probe.pem';

      // Negative control: without a panel the sandbox must deny this read.
      // If it doesn't, the build isn't actually sandboxed and the panel
      // checks below would pass without proving anything.
      expect(
        () => File(probePath).readAsBytesSync(),
        throwsA(isA<FileSystemException>()),
      );

      // Same call shape as main.dart's pickFile() for TLS certs. The
      // timeout turns "the driver never answered the panel" into a test
      // failure instead of a CI job that hangs until it's killed.
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pem']).timeout(_panelTimeout);
      expect(picked, isNotNull, reason: 'Open panel was dismissed');
      expect(picked!.files.single.path, probePath);
      final readBack = await File(probePath).readAsBytes();
      expect(utf8.decode(readBack), probeContent);

      // Same call shape as main.dart's Export / Object Store download.
      final savePath = await FilePicker.platform
          .saveFile(fileName: 'saved.txt')
          .timeout(_panelTimeout);
      expect(savePath, '$probeDir/saved.txt');
      await File(savePath!).writeAsBytes(utf8.encode('saved:$probeContent'));
    },
    skip: !Platform.isMacOS || probeDir.isEmpty,
  );
}
